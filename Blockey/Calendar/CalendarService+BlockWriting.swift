import Foundation

/// `CalendarService` already has every method `BlockWriting` asks for, with the same
/// signatures. The conformance lives here, beside the EventKit code, so `Planning/` never has
/// to know what is behind the protocol.
extension CalendarService: BlockWriting {}
