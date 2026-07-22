import AppKit

if CommandLine.arguments.contains("--self-test") {
    do {
        try SelfTests.run()
        print("Unwind native self-tests passed")
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
