import Foundation
import SQLiteShim

enum SQLiteValue {
    case text(String?)
    case int(Int?)
    case int64(Int64?)
    case bool(Bool)
    case null
}

final class DatabaseManager {
    let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            throw DatabaseError("Could not open database at \(databaseURL.path).")
        }

        try executeRaw("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentError(prefix: "Could not prepare SQL")
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw currentError(prefix: "Could not execute SQL")
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentError(prefix: "Could not prepare SQL")
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try map(statement!))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw currentError(prefix: "Could not query SQL")
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try executeRaw("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try body()
            try executeRaw("COMMIT;")
            return result
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    private func migrate() throws {
        try executeRaw(Migrations.version1)
        if try !columnExists("chatgpt_url", in: "artifacts") {
            try executeRaw("ALTER TABLE artifacts ADD COLUMN chatgpt_url TEXT;")
        }
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        let rows = try query("PRAGMA table_info(\(table));") { statement in
            DatabaseManager.string(statement, 1)
        }
        return rows.contains(column)
    }

    private func executeRaw(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw DatabaseError(message)
        }
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32

            switch value {
            case .text(let optional):
                if let optional {
                    result = sqlite3_bind_text(statement, position, optional, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            case .int(let optional):
                if let optional {
                    result = sqlite3_bind_int(statement, position, Int32(optional))
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            case .int64(let optional):
                if let optional {
                    result = sqlite3_bind_int64(statement, position, optional)
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            case .bool(let bool):
                result = sqlite3_bind_int(statement, position, bool ? 1 : 0)
            case .null:
                result = sqlite3_bind_null(statement, position)
            }

            guard result == SQLITE_OK else {
                throw currentError(prefix: "Could not bind SQL value")
            }
        }
    }

    private func currentError(prefix: String) -> DatabaseError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return DatabaseError("\(prefix): \(message)")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DatabaseManager {
    static func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    static func requiredString(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        guard let value = string(statement, index) else {
            throw DatabaseError("Expected non-null string at column \(index).")
        }
        return value
    }

    static func int(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, index))
    }

    static func bool(_ statement: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    static func date(_ statement: OpaquePointer, _ index: Int32) throws -> Date {
        let string = try requiredString(statement, index)
        guard let date = DateCoding.date(from: string) else {
            throw DatabaseError("Could not parse date: \(string).")
        }
        return date
    }

    static func optionalDate(_ statement: OpaquePointer, _ index: Int32) throws -> Date? {
        guard let string = string(statement, index) else { return nil }
        guard let date = DateCoding.date(from: string) else {
            throw DatabaseError("Could not parse date: \(string).")
        }
        return date
    }
}
