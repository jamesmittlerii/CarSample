/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
base class for our tab templates
 
 We were having issues with the templates refreshing from the subscriptions even when not selected.
 
 CarPlay is not as easy as SwiftUI - we have to manually determine if our tab is highlighted and disable refresh otherwise.
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */


import CarPlay
import Combine
import SwiftOBD2

@MainActor
class CarPlayBaseTemplateController: NSObject, @MainActor CarPlayTabControlling {
    weak var interfaceController: CPInterfaceController?
    var currentTemplate: CPTemplate?

    // Tab selection
    private var tabIndex: Int = 0
    private var isTabSelected = false
    private var tabCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // Demand-driven polling token for this controller
    let controllerToken: UUID = PIDInterestRegistry.shared.makeToken()

    // MARK: - CarPlayTabControlling

    func makeRootTemplate() -> CPTemplate {
        let template = CPListTemplate(title: "", sections: [])
        self.currentTemplate = template
        return template
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func setTabSelectionPublisher(_ publisher: AnyPublisher<Int, Never>, tabIndex: Int) {
        self.tabIndex = tabIndex
        tabCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selected in
                guard let self else { return }
                let wasSelected = self.isTabSelected
                self.isTabSelected = (selected == tabIndex)
         
                if self.isTabSelected && !wasSelected {
                    self.didBecomeVisible()
                } else if !self.isTabSelected && wasSelected {
                    // Tab just got deselected: clear any interest registered by this controller
                    PIDInterestRegistry.shared.clear(token: self.controllerToken)
                }
            }
    }

    var isTemplateVisible: Bool {
        guard let interfaceController, let currentTemplate,
              let top = interfaceController.topTemplate else { return false }
        return top === currentTemplate
    }

    func refreshIfVisible(_ action: () -> Void) {
        let allow = isTabSelected
        guard allow else { return }
        action()
    }

    func didBecomeVisible() {
        refreshIfVisible { [weak self] in
            self?.performRefresh()
            // Subclasses should also register their visible PIDs in this moment.
            self?.registerVisiblePIDs()
        }
    }

    // Subclasses should override this to perform their own refresh (e.g., refreshSection/refreshTemplate).
    func performRefresh() {
        // Default does nothing. subclass should override it.
    }

    // Subclasses can override to register their currently visible PIDs.
    func registerVisiblePIDs() {
        // Default does nothing.
    }

    // MARK: - Subscribe helpers (Equatable)

    func subscribeAndRefresh<T: Equatable>(_ publisher: Published<T>.Publisher) {
        subscribeAndRefresh(publisher, throttleSeconds: 0)
    }
    
    func subscribeAndRefresh<T: Equatable>(
        _ publisher: Published<T>.Publisher,
        throttleSeconds: TimeInterval,
        scheduler: DispatchQueue = .main,
        latest: Bool = true
    ) {
        let base = publisher
            .removeDuplicates()
            .receive(on: scheduler)
        
        let erased: AnyPublisher<T, Never>
        if throttleSeconds > 0 {
            erased = base
                .throttle(for: .seconds(throttleSeconds), scheduler: scheduler, latest: latest)
                .receive(on: scheduler)
                .eraseToAnyPublisher()
        } else {
            erased = base
                .eraseToAnyPublisher()
        }

        erased
            .sink { [weak self] _ in
                self?.refreshIfVisible {
                    // Only refresh UI on data ticks; do not re-register interest here.
                    self?.performRefresh()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Subscribe helpers (no Equatable)

    func subscribeAndRefresh<T>(_ publisher: Published<T>.Publisher) {
        subscribeAndRefresh(publisher, throttleSeconds: 0)
    }

    func subscribeAndRefresh<T>(
        _ publisher: Published<T>.Publisher,
        throttleSeconds: TimeInterval,
        scheduler: DispatchQueue = .main,
        latest: Bool = true
    ) {
        let base = publisher
            .receive(on: scheduler)

        let erased: AnyPublisher<T, Never>
        if throttleSeconds > 0 {
            erased = base
                .throttle(for: .seconds(throttleSeconds), scheduler: scheduler, latest: latest)
                .receive(on: scheduler)
                .eraseToAnyPublisher()
        } else {
            erased = base
                .eraseToAnyPublisher()
        }

        erased
            .sink { [weak self] _ in
                self?.refreshIfVisible {
                    // Only refresh UI on data ticks; do not re-register interest here.
                    self?.performRefresh()
                }
            }
            .store(in: &cancellables)
    }

    // Debug helpers
    private func id(_ obj: AnyObject?) -> String {
        guard let obj else { return "nil" }
        return String(describing: Unmanaged.passUnretained(obj).toOpaque())
    }
   
}
