import UIKit

protocol BackgroundTimerDelegate: AnyObject {
    func backgroundTimerTaskExecuted(task: UIBackgroundTaskIdentifier)
}

final class BackgroundTimer {
    weak var delegate: BackgroundTimerDelegate?
    
    init(delegate: BackgroundTimerDelegate?) {
        self.delegate = delegate
    }
    
    func executeAfterDelay(delay: TimeInterval, completion: @escaping(()->Void)) -> UIBackgroundTaskIdentifier {
        var backgroundTaskId = UIBackgroundTaskIdentifier.invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(backgroundTaskId) // The expiration Handler
        }
        
        // -- The task itself: Wait and then execute --
        wait(delay: delay,
             backgroundTaskId: backgroundTaskId,
             completion: completion
        )
        return backgroundTaskId
    }
        
    private func wait(delay: TimeInterval, backgroundTaskId: UIBackgroundTaskIdentifier, completion: @escaping(()->Void)) {
        print("BackgroundTimer: Starting \(delay) seconds countdown")
        let startTime = Date()

        DispatchQueue.global(qos: .background).async { [weak self] in
            // Waiting
            while Date().timeIntervalSince(startTime) < delay {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Executing
            DispatchQueue.main.async { [weak self] in
                print("BackgroundTimer: \(delay) seconds have passed, executing code block.")
                completion()
                self?.delegate?.backgroundTimerTaskExecuted(task: backgroundTaskId)
                UIApplication.shared.endBackgroundTask(backgroundTaskId) // Clearing
            }
        }
    }
}
