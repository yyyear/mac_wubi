// CLI entry point used with InputSourceRegistration.swift by the repair script.
// Use the repository's implementation rather than an old installed --register
// binary, which may overwrite HIToolbox preferences.
import Foundation

guard CommandLine.arguments.count == 2,
      let bundle = Bundle(path: CommandLine.arguments[1]),
      let registration = WubiRegistration(bundle) else { exit(2) }
exit(registration.ensureEnabled() ? 0 : 1)
