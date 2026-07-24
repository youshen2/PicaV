import Foundation

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
