import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func value(for keys: [String]) -> Any? {
        for key in keys {
            if let value = self[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    func string(for keys: [String]) -> String? {
        guard let value = value(for: keys) else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func integer(for keys: [String]) -> Int? {
        guard let value = value(for: keys) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    func double(for keys: [String]) -> Double? {
        guard let value = value(for: keys) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    func boolean(for keys: [String]) -> Bool? {
        guard let value = value(for: keys) else { return nil }
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    func object(for keys: [String]) -> JSONObject? {
        value(for: keys) as? JSONObject
    }

    func objects(for keys: [String]) -> [JSONObject]? {
        value(for: keys) as? [JSONObject]
    }

    func strings(for keys: [String]) -> [String] {
        guard let value = value(for: keys) else { return [] }
        if let values = value as? [String] {
            return values.filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.compactMap { item in
                if let string = item as? String { return string }
                if let number = item as? NSNumber { return number.stringValue }
                if let object = item as? JSONObject {
                    return object.string(for: ["title", "name", "tagTitle", "label"])
                }
                return nil
            }
        }
        if let string = value as? String {
            return string
                .split(whereSeparator: { ",，/|".contains($0) })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}
