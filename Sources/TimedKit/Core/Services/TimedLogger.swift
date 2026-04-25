// TimedLogger.swift — Timed Core
// Structured logging via Apple's os.Logger framework.
// Use the appropriate category logger for each subsystem.

import os

enum TimedLogger: Sendable {
    static let general   = Logger(subsystem: "com.timed.app", category: "general")
    static let dataStore = Logger(subsystem: "com.timed.app", category: "dataStore")
    static let graph     = Logger(subsystem: "com.timed.app", category: "graph")
    static let supabase  = Logger(subsystem: "com.timed.app", category: "supabase")
    static let planning  = Logger(subsystem: "com.timed.app", category: "planning")
    static let voice     = Logger(subsystem: "com.timed.app", category: "voice")
    static let calendar  = Logger(subsystem: "com.timed.app", category: "calendar")
    static let sharing   = Logger(subsystem: "com.timed.app", category: "sharing")
    static let triage    = Logger(subsystem: "com.timed.app", category: "triage")
    static let focus     = Logger(subsystem: "com.timed.app", category: "focus")
}
