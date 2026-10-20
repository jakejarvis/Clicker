import ClickerApp
import ClickerCompanion
import Foundation

// The development build. Without `--demo` it is the app as shipped; with it,
// the app runs against a scenario's made-up Apple TVs (see DemoScenario).
switch DemoScenario.parse(CommandLine.arguments) {
case nil:
    ClickerApp.run(in: .live)
case .success(let scenario):
    ClickerApp.run(in: DemoEnvironment.make(for: scenario))
case .failure(let error):
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(64)
}
