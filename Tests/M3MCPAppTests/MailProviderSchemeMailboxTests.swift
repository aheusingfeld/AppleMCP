import Foundation
import M3MCPCore
import SQLite3
import XCTest
@testable import M3MCPApp

/// Mail stores every mailbox url with a scheme (`ews://`, `imap://`, `local://`) whose host is the
/// account directory, and keeps message files below `<Folder>.mbox/<store>/Data/<digits>/Messages`.
final class MailProviderSchemeMailboxTests: XCTestCase {
    private var fixture: SchemeMailFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try SchemeMailFixture()
    }

    override func tearDownWithError() throws {
        fixture?.tearDown()
        fixture = nil
        try super.tearDownWithError()
    }

    func testReadingAnExchangeMessageResolvesItsFileWithoutWalkingTheStore() async {
        let probe = CheckpointProbe()
        let response = await fixture.withMailRoot {
            await MailProvider(cancellationCheck: probe.check).read(input: ["id": .string("794744")])
        }

        XCTAssertTrue(response.ok, response.message ?? "")
        XCTAssertTrue(
            response.items.first?.preview?.contains("exchange-body-needle") == true,
            response.items.first?.preview ?? ""
        )
        XCTAssertFalse(probe.reached(.emlxSearchEntry), "an ews:// mailbox must not fall back to walking the whole store")
    }

    func testReadingAPartialMessageInANestedImapMailboxResolvesWithoutWalkingTheStore() async {
        let probe = CheckpointProbe()
        let response = await fixture.withMailRoot {
            await MailProvider(cancellationCheck: probe.check).read(input: ["id": .string("12")])
        }

        XCTAssertTrue(response.ok, response.message ?? "")
        XCTAssertTrue(
            response.items.first?.preview?.contains("gmail-partial-needle") == true,
            response.items.first?.preview ?? ""
        )
        XCTAssertFalse(probe.reached(.emlxSearchEntry), "a nested imap:// mailbox must not fall back to walking the whole store")
    }

    func testAMessageOutsideTheExpectedShardIsFoundByWalkingOnlyItsMailbox() async {
        let probe = CheckpointProbe()
        let response = await fixture.withMailRoot {
            await MailProvider(cancellationCheck: probe.check).read(input: ["id": .string("2001")])
        }

        XCTAssertTrue(response.ok, response.message ?? "")
        XCTAssertTrue(
            response.items.first?.preview?.contains("misplaced-shard-needle") == true,
            response.items.first?.preview ?? ""
        )
        XCTAssertTrue(probe.reached(.mailboxSearchEntry), "the walk must be scoped to the message's own mailbox")
        XCTAssertFalse(probe.reached(.emlxSearchEntry), "the whole store must not be walked when the mailbox is known")
    }

    func testBodySearchFindsAMessageInASchemeMailbox() async {
        let response = await fixture.withMailRoot {
            await MailProvider().search(input: [
                "query": .string("exchange-body-needle"),
                "fields": .array([.string("body")]),
                "auto_intent": .bool(false),
                "limit": .number(10),
                "max_candidates": .number(500)
            ])
        }

        XCTAssertTrue(response.ok, response.message ?? "")
        XCTAssertEqual(response.items.map(\.id), ["794744"])
    }

    func testAnEncodedParentComponentInAMailboxUrlDoesNotReadOutsideTheStore() async {
        let response = await fixture.withMailRoot {
            await MailProvider().read(input: ["id": .string("13")])
        }

        XCTAssertTrue(response.ok, response.message ?? "")
        XCTAssertFalse(
            response.items.first?.preview?.contains("secret-outside-the-store") == true,
            "a mailbox url with an encoded '..' must not resolve outside the mail root"
        )
    }
}

private final class CheckpointProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [MailProvider.CancellationCheckpoint] = []

    func check(_ checkpoint: MailProvider.CancellationCheckpoint) -> Bool {
        lock.lock()
        seen.append(checkpoint)
        lock.unlock()
        return false
    }

    func reached(_ checkpoint: MailProvider.CancellationCheckpoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.contains(checkpoint)
    }
}

private final class SchemeMailFixture {
    static let exchangeAccount = "7EB4C59D-0000-4000-8000-000000000001"
    static let imapAccount = "985C7C64-0000-4000-8000-000000000002"

    let root: URL
    private let outside: URL

    init() throws {
        let unique = UUID().uuidString
        root = URL(fileURLWithPath: "/private/tmp/m3mail-scheme-\(unique)", isDirectory: true)
        outside = URL(fileURLWithPath: "/private/tmp/m3mail-scheme-outside-\(unique)", isDirectory: true)

        let version = root.appendingPathComponent("V10", isDirectory: true)
        let mailData = version.appendingPathComponent("MailData", isDirectory: true)
        let store = UUID().uuidString
        let exchangeMessages = version.appendingPathComponent(
            "\(Self.exchangeAccount)/Inbox.mbox/\(store)/Data/4/9/7/Messages",
            isDirectory: true
        )
        let gmailMessages = version.appendingPathComponent(
            "\(Self.imapAccount)/[Gmail].mbox/All Mail.mbox/\(store)/Data/Messages",
            isDirectory: true
        )
        let misplacedMessages = version.appendingPathComponent(
            "\(Self.exchangeAccount)/Inbox.mbox/\(store)/Data/0/2/Messages",
            isDirectory: true
        )
        let outsideMessages = outside.appendingPathComponent("Escape.mbox/Messages", isDirectory: true)

        let manager = FileManager.default
        for directory in [mailData, exchangeMessages, gmailMessages, misplacedMessages, outsideMessages] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Self.write(body: "exchange-body-needle", to: exchangeMessages.appendingPathComponent("794744.emlx"))
        try Self.write(body: "gmail-partial-needle", to: gmailMessages.appendingPathComponent("12.partial.emlx"))
        try Self.write(body: "secret-outside-the-store", to: outsideMessages.appendingPathComponent("13.emlx"))
        try Self.write(body: "misplaced-shard-needle", to: misplacedMessages.appendingPathComponent("2001.emlx"))

        var database: OpaquePointer?
        guard sqlite3_open(mailData.appendingPathComponent("Envelope Index").path, &database) == SQLITE_OK,
              let database else {
            throw Self.error("could not create the synthetic Envelope Index")
        }
        defer { sqlite3_close(database) }

        let escapeDepth = String(repeating: "%2E%2E/", count: 3)
        try Self.execute(
            """
            CREATE TABLE mailboxes (url TEXT, total_count INTEGER, unread_count INTEGER);
            INSERT INTO mailboxes (ROWID, url, total_count, unread_count) VALUES
                (1, 'ews://\(Self.exchangeAccount)/Inbox', 1, 0),
                (2, 'imap://\(Self.imapAccount)/%5BGmail%5D/All%20Mail', 1, 0),
                (3, 'ews://\(Self.exchangeAccount)/\(escapeDepth)m3mail-scheme-outside-\(unique)/Escape', 1, 0);
            CREATE TABLE subjects (subject TEXT);
            INSERT INTO subjects (ROWID, subject) VALUES (1, 'Exchange message'), (2, 'Gmail message'), (3, 'Escape');
            CREATE TABLE addresses (address TEXT, comment TEXT);
            INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'sender@example.test', 'Sender');
            CREATE TABLE messages (
                message_id TEXT, subject INTEGER, sender INTEGER, date_received REAL,
                read INTEGER, deleted INTEGER, junk INTEGER, mailbox INTEGER
            );
            CREATE TABLE recipients (message INTEGER, address INTEGER);
            INSERT INTO messages (ROWID, message_id, subject, sender, date_received, read, deleted, junk, mailbox) VALUES
                (794744, 'm794744', 1, 1, \(Date().timeIntervalSince1970), 0, 0, 0, 1),
                (12, 'm12', 2, 1, \(Date().timeIntervalSince1970), 0, 0, 0, 2),
                (13, 'm13', 3, 1, \(Date().timeIntervalSince1970), 0, 0, 0, 3),
                (2001, 'm2001', 1, 1, \(Date().timeIntervalSince1970), 0, 0, 0, 1);
            """,
            on: database
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    func withMailRoot<T>(_ operation: () async throws -> T) async rethrows -> T {
        let key = MailProvider.mailRootEnvironmentKey
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, root.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await operation()
    }

    private static func write(body: String, to url: URL) throws {
        let email = "Content-Type: text/plain; charset=utf-8\r\n\r\n\(body)\r\n"
        try Data("\(email.utf8.count)\n\(email)".utf8).write(to: url)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw error(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "MailProviderSchemeMailboxTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
