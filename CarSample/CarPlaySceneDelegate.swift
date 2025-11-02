//
//  CarPlaySceneDelegate.swift
//  CarPlay
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit
// CarPlay App Lifecycle

import CarPlay
import os.log

func drawGaugeImage(for value: Double, size: CGSize = CGSize(width: 40, height: 40)) -> UIImage {
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
        let lineWidth: CGFloat = max(2, min(size.width, size.height) * 0.15)
        let radius = (min(size.width, size.height) - lineWidth) / 2.0

        // Angles (start at top, clockwise)
        let startAngle: CGFloat = -.pi / 2
        let endAngle: CGFloat = startAngle + 2 * .pi

        // Background track
        let trackPath = UIBezierPath(arcCenter: center,
                                     radius: radius,
                                     startAngle: startAngle,
                                     endAngle: endAngle,
                                     clockwise: true)
        trackPath.lineWidth = lineWidth
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

        // Progress arc
        let progressEnd = startAngle + (endAngle - startAngle) * progress
        let progressPath = UIBezierPath(arcCenter: center,
                                        radius: radius,
                                        startAngle: startAngle,
                                        endAngle: progressEnd,
                                        clockwise: true)
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = lineWidth
        UIColor.systemBlue.setStroke()
        progressPath.stroke()

        // Optional: thin outer border for clarity
        let outerBorder = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        outerBorder.lineWidth = 1
        UIColor.systemGray4.setStroke()
        outerBorder.stroke()
    }
}



class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    let logger = Logger()
    
    // MARK: - Album model and UI state
    struct Album {
        var title: String
        var artist: String
        var price: Double
    }
    
    // Mutable data source
    private var albums: [Album] = [
        Album(title: "Rubber Soul", artist: "The Beatles", price: 12.99),
        Album(title: "Kind of Blue", artist: "Miles Davis", price: 10.99),
        Album(title: "Rumours", artist: "Fleetwood Mac", price: 11.49),
        Album(title: "The Dark Side of the Moon", artist: "Pink Floyd", price: 13.99)
    ]
    
    // Keep references to update UI efficiently
    private var listItems: [CPListItem] = []
    private var albumsListTemplate: CPListTemplate?
    
    // Background task to update prices
    private var priceUpdateTask: Task<Void, Never>?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        
        let gridButton = CPGridButton(titleVariants: ["Albums"],
                                      image: UIImage(systemName: "list.triangle")!)
        { [weak self] _ in
            guard let self else { return }
            let listTemplate = self.listTemplate()
            interfaceController.pushTemplate(listTemplate,
                                             animated: true,
                                             completion: nil)
        }
        
        let gridTemplate = CPGridTemplate(title: "A Grid Interface", gridButtons:  [gridButton])
        
        // SwiftC apparently requires the explicit inclusion of the completion parameter,
        // otherwise it will throw a warning
        interfaceController.setRootTemplate(gridTemplate,
                                            animated: true,
                                            completion: nil)
        
        // Start background price updates when CarPlay connects
        startPriceUpdates()
    }

    func listTemplate() -> CPListTemplate {
        // Build CPListItems from current albums and keep references
        listItems = albums.map { album in
            
            let dynamicImage = drawGaugeImage(for: album.price)
            
            let item = CPListItem(
                text: album.title,
                detailText: "\(album.artist) • $\(String(format: "%.2f", album.price))",
                image: dynamicImage
            )
            // Set playbackProgress as price percentage of $20 (clamped 0...1)
            let progress = min(1.0, max(0.0, album.price / 20.0))
            item.playbackProgress = CGFloat(progress)
            item.handler = { [weak self] _, completion in
                self?.logger.info("Item selected: \(album.title, privacy: .public)")
                completion()
            }
            return item
        }
        
        let section = CPListSection(items: listItems)
        let template = CPListTemplate(title: "Albums", sections: [section])
        albumsListTemplate = template
        return template
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        // Stop background updates when CarPlay disconnects
        priceUpdateTask?.cancel()
        priceUpdateTask = nil
    }
    
    // MARK: - Background price updates
    
    private func startPriceUpdates() {
        // Avoid multiple tasks
        priceUpdateTask?.cancel()
        priceUpdateTask = Task.detached { [weak self] in
            guard let self else { return }
            // Randomly update prices while connected
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.randomlyAdjustPrices()
                await self.refreshAlbumListIfVisible()
            }
        }
    }
    
    @MainActor
    private func refreshAlbumListIfVisible() {
        guard let currentTemplate = albumsListTemplate else { return }
        
        // Rebuild CPListItems to reflect new prices (CPListItem text is read-only)
        listItems = albums.map { album in
            let dynamicImage = drawGaugeImage(for: album.price)
            let item = CPListItem(
                text: album.title,
                detailText: "\(album.artist) • $\(String(format: "%.2f", album.price))",
                image: dynamicImage
            )
            // Update playbackProgress to match the latest price
            let progress = min(1.0, max(0.0, album.price / 20.0))
            item.playbackProgress = CGFloat(progress)
            item.handler = { [weak self] _, completion in
                self?.logger.info("Item selected: \(album.title, privacy: .public)")
                completion()
            }
            return item
        }
        
        // Update the section in place (iOS 14+)
        let newSection = CPListSection(items: listItems)
        currentTemplate.updateSections([newSection])
    }
    
    @MainActor
    private func randomlyAdjustPrices() {
        // Adjust each price by +/- up to 50 cents, then clamp between $0.00 and $20.00
        for i in albums.indices {
            let delta = Double.random(in: -0.5...0.5)
            let unclamped = albums[i].price + delta
            let clamped = min(20.0, max(0.0, unclamped))
            albums[i].price = (clamped * 100).rounded() / 100 // round to cents
        }
        logger.debug("Prices updated in background")
    }
}
