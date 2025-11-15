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

@MainActor
class CarPlayBaseTemplateController: NSObject, @MainActor CarPlayTabControlling {
    weak var interfaceController: CPInterfaceController?
    var currentTemplate: CPTemplate?

    // Tab selection
    private var tabIndex: Int = 0
    private var isTabSelected = false
    private var tabCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CarPlayTabControlling

    func makeRootTemplate() -> CPTemplate {
        // Subclasses are expected to override and return their concrete template.
        // Provide a harmless empty template to satisfy the protocol if not overridden.
        let template = CPListTemplate(title: "", sections: [])
        self.currentTemplate = template
        return template
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    // Injected from Scene
    // keep track of which tab got selected
    func setTabSelectionPublisher(_ publisher: AnyPublisher<Int, Never>, tabIndex: Int) {
        self.tabIndex = tabIndex
        tabCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selected in
                guard let self else { return }
                let wasSelected = self.isTabSelected
                self.isTabSelected = (selected == tabIndex)
         
                // If this tab just became selected, force a refresh now.
                if self.isTabSelected && !wasSelected {
                    self.didBecomeVisible()
                }
            }
    }

    // Strictly on-screen check
    var isTemplateVisible: Bool {
        guard let interfaceController, let currentTemplate,
              let top = interfaceController.topTemplate else { return false }
        return top === currentTemplate
    }

    // Gate UI updates by tab selection (and optionally visibility)
    func refreshIfVisible(_ action: () -> Void) {
        let allow = isTabSelected
        guard allow else { return }
        action()
    }

    // Called when the tab becomes selected. Subclasses can override, but default forces a guarded refresh.
    func didBecomeVisible() {
        refreshIfVisible { [weak self] in
            self?.performRefresh()
        }
    }
    
    // MARK: - Subscribe helpers (Equatable: removeDuplicates)

    // Convenience: subscribe and refresh without throttling (Equatable)
    func subscribeAndRefresh<T: Equatable>(_ publisher: Published<T>.Publisher) {
        subscribeAndRefresh(publisher, throttleSeconds: 0)
    }
    
    // Subscribe and refresh with optional throttling (Equatable)
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
                    self?.performRefresh()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Subscribe helpers (no Equatable: no removeDuplicates)

    // Convenience: subscribe and refresh without throttling (non-Equatable)
    func subscribeAndRefresh<T>(_ publisher: Published<T>.Publisher) {
        subscribeAndRefresh(publisher, throttleSeconds: 0)
    }

    // Subscribe and refresh with optional throttling (non-Equatable)
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
                    self?.performRefresh()
                }
            }
            .store(in: &cancellables)
    }

    // Subclasses should override this to perform their own refresh (e.g., refreshSection/refreshTemplate).
    func performRefresh() {
        // Default does nothing. subclass should override it.
    }

    // Debug helpers
    private func id(_ obj: AnyObject?) -> String {
        guard let obj else { return "nil" }
        return String(describing: Unmanaged.passUnretained(obj).toOpaque())
    }
   
}
