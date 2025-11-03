//
//  CarPlaySceneDelegate.swift
//  CarPlay
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit
import SwiftOBD2
// CarPlay App Lifecycle

import CarPlay
import os.log
import Combine

func drawGaugeImage(for value: Double, size: CGSize = CPListImageRowItemElement.maximumImageSize) -> UIImage {
    // Clamp value to 0...20, then normalize to 0...1
    let clamped = max(0.0, min(20.0, value))
    let progress = CGFloat(clamped / 20.0)

    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { ctx in
        let rect = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Make it a ring that fits within the smallest dimension
        let lineWidth: CGFloat = max(4, min(size.width, size.height) * 0.25)
        let radius = (min(size.width, size.height) - lineWidth) / 2.0

        // Angles for a speedometer-style gauge (from 8 o'clock to 4 o'clock)
        // This creates a 240-degree arc.
        let startAngle: CGFloat = (5.0 / 6.0) * .pi      // ~8 o'clock position
        let sweepAngle: CGFloat = (4.0 / 3.0) * .pi      // 240-degree sweep
        let endAngle: CGFloat = startAngle + sweepAngle  // ~4 o'clock position

        // Background track
        let trackPath = UIBezierPath(arcCenter: center,
                                     radius: radius,
                                     startAngle: startAngle,
                                     endAngle: endAngle,
                                     clockwise: true)
        trackPath.lineWidth = lineWidth
        trackPath.lineCapStyle = .round // Rounded ends for a softer look
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

        // Progress arc
        let progressEndAngle = startAngle + (sweepAngle * progress)
        let progressPath = UIBezierPath(arcCenter: center,
                                        radius: radius,
                                        startAngle: startAngle,
                                        endAngle: progressEndAngle,
                                        clockwise: true)
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = lineWidth
        UIColor.systemBlue.setStroke()
        progressPath.stroke()
    }
}



class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    let logger = Logger()
    
    // Local OBD service instance
    let obdService = OBDService(
        connectionType: .wifi,
        host: ConfigData.shared.wifiHost,
        port: ConfigData.shared.wifiPort
    )
    
    // Combine cancellables for OBD streaming
    private var cancellables = Set<AnyCancellable>()
    // Optional: hold last measurements if you want to use them to update UI
    private var latestMeasurements: [OBDCommand: MeasurementResult] = [:]
    
    
    
    // Keep references to update UI efficiently
    private var SensorsListTemplate: CPListTemplate?
    
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController) {

        print("CPList maximumGridButtonImageSize: \(CPListTemplate.maximumGridButtonImageSize)")
        print("CPGrid maximumGridButtonImageSize: \(CPGridTemplate.maximumGridButtonImageSize)")
        print("CPListImageRowItemElement maximumImageSize: \(CPListImageRowItemElement.maximumImageSize)")
        
        self.interfaceController = interfaceController
        
        // Build the three tabs
        let gaugesTemplate = self.makeSensorsListTemplate()
        gaugesTemplate.tabTitle = "Gauges"
        gaugesTemplate.tabImage = symbolImage(named: "gauge")

        let diagnosticsTemplate = self.makeDiagnosticsTemplate()
        diagnosticsTemplate.tabTitle = "Diagnostics"
        diagnosticsTemplate.tabImage = symbolImage(named: "wrench.and.screwdriver")

        let settingsTemplate = self.makeSettingsTemplate()
        settingsTemplate.tabTitle = "Settings"
        settingsTemplate.tabImage = symbolImage(named: "gear")

        let tabBar = CPTabBarTemplate(templates: [gaugesTemplate, diagnosticsTemplate, settingsTemplate])
        
        interfaceController.setRootTemplate(tabBar,
                                            animated: true,
                                            completion: nil)
        
        
        // Start OBD-II connection asynchronously
        Task { [weak self] in
            guard let self else { return }
            do {
                let obd2Info = try await obdService.startConnection()
                // Optionally log or use obd2Info here (e.g., VIN or protocol)
                self.logger.info("OBD-II connected successfully.")
                _ = obd2Info // prevent unused variable warning if not used yet

                // After a successful connection, start continuous sensor updates
                self.startContinuousOBDUpdates()
            } catch {
                self.logger.error("OBD-II connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func startContinuousOBDUpdates() {
        // Create an individual subscription per PID (as required)
        for pid in OBDPIDLibrary.standard {
            let command = OBDCommand.mode1(pid.pid)
            obdService
                .startContinuousUpdates([command])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            self?.logger.error("Continuous OBD updates failed: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { [weak self] measurements in
                        guard let self else { return }
                        // Merge the incoming measurement(s) into the dictionary so we keep the latest per sensor.
                        for (cmd, result) in measurements {
                            self.latestMeasurements[cmd] = result
                        }
                        // Trigger UI updates based on the combined latest values
                        self.refreshSensorListIfVisible()
                    }
                )
                .store(in: &cancellables)
        }
    }

    func symbolImage(named name: String) -> UIImage? {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: name)
        } else {
            return nil
        }
    }

    
    
   
    
   
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        // Stop background updates when CarPlay disconnects
       
        // Cancel OBD streaming subscriptions on disconnect
        cancellables.removeAll()
    }
    
    // MARK: - Gauges (sensors) section using OBDPIDLibrary
    @MainActor
    private func makeGaugesSection() -> CPListSection {
        let sensors = OBDPIDLibrary.standard

        // Helper to get current value for a PID
        func currentValue(for pid: OBDPID) -> Double? {
            let command = OBDCommand.mode1(pid.pid)
            return latestMeasurements[command]?.value
        }

        // Build one row element per sensor
        let rowElements: [CPListImageRowItemRowElement] = sensors.map { pid in
            let value = currentValue(for: pid) ?? pid.typicalRange.min
            // Normalize value to 0...1 within the typical range, then map to 0...20 for our gauge drawer
            let normalized = pid.typicalRange.normalizedPosition(for: value)
            let gaugeValue = normalized * 20.0
            let image = drawGaugeImage(for: gaugeValue)

            let subtitle: String = {
                if let v = currentValue(for: pid) {
                    return String(format: "%.1f %@", v, pid.units)
                } else {
                    return "— \(pid.units)"
                }
            }()

            return CPListImageRowItemRowElement(
                image: image,
                title: pid.name,
                subtitle: subtitle
            )
        }

        // Create a single row item to contain all sensors
        let item = CPListImageRowItem(
            text: "",
            elements: rowElements,
            allowsMultipleLines: true
        )
        item.handler = { _, completion in
            completion()
        }

        // Handler for individual sensor taps
        item.listImageRowHandler = { [weak self] _, index, completion in
            guard let self = self else {
                completion()
                return
            }
            guard index >= 0 && index < sensors.count else {
                completion()
                return
            }
            let tappedPID = sensors[index]
            Task { @MainActor in
                await self.presentSensorTemplate(for: tappedPID)
                completion()
            }
        }

        return CPListSection(items: [item])
    }
    
    // Replaces the previous album-based template with a sensor-based template
    func makeSensorsListTemplate() -> CPListTemplate {
        let section = makeGaugesSection()
        let template = CPListTemplate(title: "", sections: [section])

        self.SensorsListTemplate = template
        return template
    }

    // MARK: - Diagnostics and Settings tabs

    private func makeDiagnosticsTemplate() -> CPListTemplate {
        let items: [CPListItem] = [
            {
                let count = exampleOBDCodes.count
                let statusText = count == 0 ? "No DTCs" : "\(count) Code\(count == 1 ? "" : "s")"
                let i = CPListItem(text: "OBD-II Status", detailText: statusText)
                i.handler = { [weak self] _, completion in
                    guard let self else { completion(); return }
                    let obdTemplate = self.makeOBDListTemplate(codes: exampleOBDCodes)
                    self.interfaceController?.pushTemplate(obdTemplate, animated: true, completion: nil)
                    completion()
                }
                return i
            }(),
            {
                let i = CPListItem(text: "Battery Health", detailText: "Good")
                i.handler = { _, completion in completion() }
                return i
            }(),
            {
                let i = CPListItem(text: "Tire Pressure", detailText: "Front: 36 psi, Rear: 34 psi")
                i.handler = { _, completion in completion() }
                return i
            }()
        ]
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Diagnostics", sections: [section])
        return template
    }

    private func makeSettingsTemplate() -> CPListTemplate {
        let items: [CPListItem] = [
            {
                let i = CPListItem(text: "Units", detailText: "Metric")
                i.handler = { _, completion in completion() }
                return i
            }(),
            {
                let i = CPListItem(text: "Theme", detailText: "Automatic")
                i.handler = { _, completion in completion() }
                return i
            }(),
            {
                let i = CPListItem(text: "About", detailText: "Version 1.0")
                i.handler = { _, completion in completion() }
                return i
            }()
        ]
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Settings", sections: [section])
        return template
    }

    @MainActor
    private func refreshSensorListIfVisible() {
        guard let currentTemplate = SensorsListTemplate else { return }
        let updatedSection = makeGaugesSection()
        currentTemplate.updateSections([updatedSection])
    }

   
}

// MARK: - OBD-II Templates
extension CarPlaySceneDelegate {
    private func makeOBDListTemplate(codes: [OBDCode]) -> CPListTemplate {
        // Map severity to a system image name for quick visual cue
        func imageName(for severity: OBDCode.Severity) -> String {
            switch severity {
            case .low: return "exclamationmark.circle"
            case .moderate: return "exclamationmark.triangle"
            case .high: return "bolt.trianglebadge.exclamationmark"
            case .critical: return "xmark.octagon"
            }
        }

        let items: [CPListItem] = codes.map { code in
            let title = "\(code.code) • \(code.title)"
            let item = CPListItem(text: title, detailText: code.severity.rawValue)
            if let img = symbolImage(named: imageName(for: code.severity)) {
                item.setImage(img)
            }
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.presentOBDDetail(for: code)
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items)
        let title = "OBD-II Diagnostic Codes"
        return CPListTemplate(title: title, sections: [section])
    }

    @MainActor
    private func presentOBDDetail(for code: OBDCode) async {
        let items: [CPInformationItem] = [
            CPInformationItem(title: "Code", detail: code.code),
            CPInformationItem(title: "Title", detail: code.title),
            CPInformationItem(title: "Severity", detail: code.severity.rawValue),
            CPInformationItem(title: "Description", detail: code.description)
        ]
        let template = CPInformationTemplate(title: "DTC \(code.code)", layout: .twoColumn, items: items, actions: [])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // Sensor detail presenter
    @MainActor
    private func presentSensorTemplate(for pid: OBDPID) async {
        let command = OBDCommand.mode1(pid.pid)
        let current = latestMeasurements[command]?.value

        var items: [CPInformationItem] = []
        if let current = current {
            items.append(CPInformationItem(title: "Current", detail: String(format: "%.2f %@", current, pid.units)))
        } else {
            items.append(CPInformationItem(title: "Current", detail: "— \(pid.units)"))
        }
        items.append(CPInformationItem(title: "Units", detail: pid.units))
        items.append(CPInformationItem(title: "Formula", detail: pid.formula))
        items.append(CPInformationItem(title: "Typical Range", detail: String(format: "%.1f – %.1f %@", pid.typicalRange.min, pid.typicalRange.max, pid.units)))
        if let warn = pid.warningRange {
            items.append(CPInformationItem(title: "Warning Range", detail: String(format: "%.1f – %.1f %@", warn.min, warn.max, pid.units)))
        }
        if let danger = pid.dangerRange {
            items.append(CPInformationItem(title: "Danger Range", detail: String(format: "%.1f – %.1f %@", danger.min, danger.max, pid.units)))
        }
        if let notes = pid.notes {
            items.append(CPInformationItem(title: "Notes", detail: notes))
        }

        let template = CPInformationTemplate(title: pid.name, layout: .twoColumn, items: items, actions: [])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
}
