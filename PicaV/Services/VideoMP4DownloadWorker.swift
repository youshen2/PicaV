import Foundation
import Libavcodec
import Libavformat
import Libavutil

final class VideoMP4DownloadWorker: @unchecked Sendable {
    struct Configuration: Sendable {
        let sourceURL: URL
        let temporaryURL: URL
        let destinationURL: URL
        let proxyURL: URL?
    }

    init(
        configuration: Configuration,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.configuration = configuration
        self.progress = progress
        self.completion = completion
    }

    func start() {
        queue.async { [self] in
            completion(Result { try download() })
        }
    }

    func pause() {
        condition.lock()
        if state == .running {
            state = .paused
        }
        condition.unlock()
    }

    func resume() {
        condition.lock()
        if state == .paused {
            state = .running
            condition.broadcast()
        }
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        state = .cancelled
        condition.broadcast()
        condition.unlock()
    }

    private func download() throws -> URL {
        _ = Self.networkInitialization
        try removeExistingOutputFiles()

        var inputContext = avformat_alloc_context()
        guard let allocatedInputContext = inputContext else {
            throw VideoMP4DownloadError.openInput("无法创建媒体读取器")
        }
        allocatedInputContext.pointee.interrupt_callback = AVIOInterruptCB(
            callback: { opaque in
                guard let opaque else { return 0 }
                let worker = Unmanaged<VideoMP4DownloadWorker>
                    .fromOpaque(opaque)
                    .takeUnretainedValue()
                return worker.isCancelled ? 1 : 0
            },
            opaque: Unmanaged.passUnretained(self).toOpaque()
        )

        var inputOptions: OpaquePointer?
        av_dict_set(&inputOptions, "rw_timeout", "30000000", 0)
        av_dict_set(&inputOptions, "reconnect", "1", 0)
        av_dict_set(&inputOptions, "reconnect_streamed", "1", 0)
        if let proxyURL = configuration.proxyURL?.absoluteString {
            av_dict_set(&inputOptions, "http_proxy", proxyURL, 0)
        }

        let source = configuration.sourceURL.absoluteString
        let openResult = avformat_open_input(
            &inputContext,
            source,
            nil,
            &inputOptions
        )
        av_dict_free(&inputOptions)
        guard openResult >= 0, let inputContext else {
            avformat_close_input(&inputContext)
            throw VideoMP4DownloadError.openInput(
                Self.errorMessage(for: openResult)
            )
        }
        defer {
            inputContext.pointee.interrupt_callback.opaque = nil
            inputContext.pointee.interrupt_callback.callback = nil
            var context: UnsafeMutablePointer<AVFormatContext>? = inputContext
            avformat_close_input(&context)
        }

        let streamInfoResult = avformat_find_stream_info(inputContext, nil)
        guard streamInfoResult >= 0 else {
            throw VideoMP4DownloadError.openInput(
                Self.errorMessage(for: streamInfoResult)
            )
        }
        try checkCancellation()

        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        let destinationPath = configuration.temporaryURL.path
        let outputResult = avformat_alloc_output_context2(
            &outputContext,
            nil,
            "mp4",
            destinationPath
        )
        guard outputResult >= 0, let outputContext else {
            throw VideoMP4DownloadError.createOutput(
                Self.errorMessage(for: outputResult)
            )
        }
        defer {
            if outputContext.pointee.pb != nil {
                avio_closep(&outputContext.pointee.pb)
            }
            avformat_free_context(outputContext)
        }

        let streamMapping = try configureStreams(
            inputContext: inputContext,
            outputContext: outputContext
        )
        let openOutputResult = avio_open(
            &outputContext.pointee.pb,
            destinationPath,
            AVIO_FLAG_WRITE
        )
        guard openOutputResult >= 0 else {
            throw VideoMP4DownloadError.createOutput(
                Self.errorMessage(for: openOutputResult)
            )
        }

        var outputOptions: OpaquePointer?
        av_dict_set(&outputOptions, "movflags", "+faststart", 0)
        let headerResult = avformat_write_header(
            outputContext,
            &outputOptions
        )
        av_dict_free(&outputOptions)
        guard headerResult >= 0 else {
            throw VideoMP4DownloadError.createOutput(
                Self.errorMessage(for: headerResult)
            )
        }

        try copyPackets(
            inputContext: inputContext,
            outputContext: outputContext,
            streamMapping: streamMapping
        )
        try checkCancellation()
        let trailerResult = av_write_trailer(outputContext)
        guard trailerResult >= 0 else {
            throw VideoMP4DownloadError.finalizeOutput(
                Self.errorMessage(for: trailerResult)
            )
        }
        if outputContext.pointee.pb != nil {
            avio_closep(&outputContext.pointee.pb)
        }

        try FileManager.default.moveItem(
            at: configuration.temporaryURL,
            to: configuration.destinationURL
        )
        progress(1)
        return configuration.destinationURL
    }

    private func configureStreams(
        inputContext: UnsafeMutablePointer<AVFormatContext>,
        outputContext: UnsafeMutablePointer<AVFormatContext>
    ) throws -> [Int: Int] {
        let videoIndex = av_find_best_stream(
            inputContext,
            AVMEDIA_TYPE_VIDEO,
            -1,
            -1,
            nil,
            0
        )
        guard videoIndex >= 0 else {
            throw VideoMP4DownloadError.unsupportedSource
        }
        let audioIndex = av_find_best_stream(
            inputContext,
            AVMEDIA_TYPE_AUDIO,
            -1,
            videoIndex,
            nil,
            0
        )

        var mapping = [Int: Int]()
        for inputIndex in [videoIndex, audioIndex] where inputIndex >= 0 {
            guard let inputStream = inputContext.pointee.streams[
                Int(inputIndex)
            ], let outputStream = avformat_new_stream(
                outputContext,
                nil
            ) else {
                throw VideoMP4DownloadError.createOutput(
                    "无法创建 MP4 音视频轨道"
                )
            }
            let copyResult = avcodec_parameters_copy(
                outputStream.pointee.codecpar,
                inputStream.pointee.codecpar
            )
            guard copyResult >= 0 else {
                throw VideoMP4DownloadError.createOutput(
                    Self.errorMessage(for: copyResult)
                )
            }
            outputStream.pointee.time_base = inputStream.pointee.time_base
            if inputStream.pointee.codecpar.pointee.codec_id
                == AV_CODEC_ID_HEVC {
                outputStream.pointee.codecpar.pointee.codec_tag = 0x31637668
            } else {
                outputStream.pointee.codecpar.pointee.codec_tag = 0
            }
            mapping[Int(inputIndex)] = Int(outputStream.pointee.index)
        }
        return mapping
    }

    private func copyPackets(
        inputContext: UnsafeMutablePointer<AVFormatContext>,
        outputContext: UnsafeMutablePointer<AVFormatContext>,
        streamMapping: [Int: Int]
    ) throws {
        let duration = inputContext.pointee.duration > 0
            ? Double(inputContext.pointee.duration) / Double(AV_TIME_BASE)
            : 0
        var packet = AVPacket()

        while true {
            try waitWhilePaused()
            let readResult = av_read_frame(inputContext, &packet)
            if readResult < 0 {
                av_packet_unref(&packet)
                if readResult == Self.endOfFileError {
                    return
                }
                try checkCancellation()
                throw VideoMP4DownloadError.readSource(
                    Self.errorMessage(for: readResult)
                )
            }
            defer { av_packet_unref(&packet) }

            let inputIndex = Int(packet.stream_index)
            guard let outputIndex = streamMapping[inputIndex],
                  let inputStream = inputContext.pointee.streams[inputIndex],
                  let outputStream = outputContext.pointee.streams[
                      outputIndex
                  ] else {
                continue
            }

            let timestamp = packet.pts != Self.noTimestamp
                ? packet.pts
                : packet.dts
            if duration > 0, timestamp != Self.noTimestamp {
                let seconds = Double(timestamp)
                    * av_q2d(inputStream.pointee.time_base)
                if seconds.isFinite {
                    progress(min(max(seconds / duration, 0), 0.999))
                }
            }

            packet.stream_index = Int32(outputIndex)
            av_packet_rescale_ts(
                &packet,
                inputStream.pointee.time_base,
                outputStream.pointee.time_base
            )
            packet.pos = -1
            let writeResult = av_interleaved_write_frame(
                outputContext,
                &packet
            )
            guard writeResult >= 0 else {
                throw VideoMP4DownloadError.writeOutput(
                    Self.errorMessage(for: writeResult)
                )
            }
        }
    }

    private func removeExistingOutputFiles() throws {
        let fileManager = FileManager.default
        for url in [
            configuration.temporaryURL,
            configuration.destinationURL
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func waitWhilePaused() throws {
        condition.lock()
        while state == .paused {
            condition.wait()
        }
        let cancelled = state == .cancelled
        condition.unlock()
        if cancelled {
            throw CancellationError()
        }
    }

    private func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    private var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return state == .cancelled
    }

    private static func errorMessage(for code: Int32) -> String {
        var buffer = [CChar](
            repeating: 0,
            count: Int(AV_ERROR_MAX_STRING_SIZE)
        )
        av_strerror(code, &buffer, buffer.count)
        let message = String(cString: buffer)
        return message.isEmpty ? "FFmpeg 错误码 \(code)" : message
    }

    private enum State {
        case running
        case paused
        case cancelled
    }

    private let configuration: Configuration
    private let progress: @Sendable (Double) -> Void
    private let completion: @Sendable (Result<URL, Error>) -> Void
    private let condition = NSCondition()
    private let queue = DispatchQueue(
        label: "work.picav.video-mp4-download",
        qos: .utility
    )
    private var state = State.running
    // These C macros are not exported by FFmpegKit's Swift module map.
    private static let endOfFileError: Int32 = -541_478_725
    private static let noTimestamp = Int64.min
    private static let networkInitialization = avformat_network_init()
}

private enum VideoMP4DownloadError: LocalizedError {
    case openInput(String)
    case createOutput(String)
    case readSource(String)
    case writeOutput(String)
    case finalizeOutput(String)
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .openInput(let detail):
            return "无法读取播放源：\(detail)"
        case .createOutput(let detail):
            return "无法创建 MP4 文件：\(detail)"
        case .readSource(let detail):
            return "下载视频数据失败：\(detail)"
        case .writeOutput(let detail):
            return "写入 MP4 文件失败：\(detail)"
        case .finalizeOutput(let detail):
            return "完成 MP4 文件失败：\(detail)"
        case .unsupportedSource:
            return "播放源中没有可下载的视频轨道。"
        }
    }
}
