import Foundation
import DoctorCore

@main
struct DoctorCLI {
    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let allowed: Set<String> = ["--json", "--demo-mac-pro", "--demo-macbook-pro", "--demo-unavailable", "--help"]
        guard arguments.isSubset(of: allowed) else {
            FileHandle.standardError.write(Data("Unknown option. Run --help for usage.\n".utf8))
            Foundation.exit(2)
        }
        if arguments.contains("--help") {
            print("oclp-doctor [--json] [--demo-mac-pro | --demo-macbook-pro | --demo-unavailable]\nRead-only diagnostics with seven-day sleep/wake evidence. Results are written to local standard output only.")
            return
        }
        let result: SystemInfo
        if arguments.contains("--demo-mac-pro") { result = DemoData.snapshot(model: .macPro) }
        else if arguments.contains("--demo-macbook-pro") { result = DemoData.snapshot(model: .macBookPro) }
        else if arguments.contains("--demo-unavailable") { result = DemoData.snapshot(model: .unavailable) }
        else { result = await DiagnosticEngine().collect() }
        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var value = encoder.singleValueContainer()
                try value.encode(LogTimestamp.iso8601Milliseconds(date))
            }
            do { print(String(decoding: try encoder.encode(result), as: UTF8.self)) }
            catch { FileHandle.standardError.write(Data("Unable to encode the report.\n".utf8)); Foundation.exit(1) }
        } else { print(ReportGenerator.generate(result)) }
    }
}
