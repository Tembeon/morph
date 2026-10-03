import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = RecordingWindow(windowScene: windowScene)
        let sceneName = ProcessInfo.processInfo.environment["PROBE_SCENE"]
            ?? UserDefaults.standard.string(forKey: "scene")
            ?? "segmented"
        if let d = ProcessInfo.processInfo.environment["PROBE_DARK"] { window.overrideUserInterfaceStyle = d == "1" ? .dark : .light }
        window.rootViewController = Scenes.make(sceneName)
        window.makeKeyAndVisible()
        self.window = window
        Recorder.shared.start(scene: sceneName, window: window)
    }
}
