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

func drawGaugeImage(for value: Double, size: CGSize = CPGridTemplate.maximumGridButtonImageSize) -> UIImage {
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
    
    // MARK: - Album model and UI state
    struct Album {
        var title: String
        var artist: String
        var price: Double
        var year: Int
        var genre: String
        var lengthInMinutes: Int
        var songs: [String]
    }
    
    // Mutable data source
    private var albums: [Album] = [
        Album(title: "Rubber Soul", artist: "The Beatles", price: 12.99, year: 1965, genre: "Folk Rock", lengthInMinutes: 35, songs: ["Drive My Car", "Norwegian Wood", "You Won't See Me", "Nowhere Man", "Think for Yourself", "The Word", "Michelle", "What Goes On", "Girl", "I'm Looking Through You", "In My Life", "Wait", "If I Needed Someone", "Run for Your Life"]),
        Album(title: "Kind of Blue", artist: "Miles Davis", price: 10.99, year: 1959, genre: "Jazz", lengthInMinutes: 45, songs: ["So What", "Freddie Freeloader", "Blue in Green", "All Blues", "Flamenco Sketches"]),
        Album(title: "Rumours", artist: "Fleetwood Mac", price: 11.49, year: 1977, genre: "Pop Rock", lengthInMinutes: 40, songs: ["Second Hand News", "Dreams", "Never Going Back Again", "Don't Stop", "Go Your Own Way", "Songbird", "The Chain", "You Make Loving Fun", "I Don't Want to Know", "Oh Daddy", "Gold Dust Woman"]),
        Album(title: "The Dark Side of the Moon", artist: "Pink Floyd", price: 13.99, year: 1973, genre: "Progressive Rock", lengthInMinutes: 43, songs: ["Speak to Me", "Breathe", "On the Run", "Time", "The Great Gig in the Sky", "Money", "Us and Them", "Any Colour You Like", "Brain Damage", "Eclipse"]),
        Album(title: "Abbey Road", artist: "The Beatles", price: 14.49, year: 1969, genre: "Rock", lengthInMinutes: 47, songs: ["Come Together", "Something", "Maxwell's Silver Hammer", "Oh! Darling", "Octopus's Garden", "I Want You (She's So Heavy)", "Here Comes the Sun", "Because", "You Never Give Me Your Money", "Sun King", "Mean Mr. Mustard", "Polythene Pam", "She Came in Through the Bathroom Window", "Golden Slumbers", "Carry That Weight", "The End", "Her Majesty"]),
        Album(title: "Back in Black", artist: "AC/DC", price: 12.29, year: 1980, genre: "Hard Rock", lengthInMinutes: 42, songs: ["Hells Bells", "Shoot to Thrill", "What Do You Do for Money Honey", "Given the Dog a Bone", "Let Me Put My Love Into You", "Back in Black", "You Shook Me All Night Long", "Have a Drink on Me", "Shake a Leg", "Rock and Roll Ain't Noise Pollution"]),
        Album(title: "Thriller", artist: "Michael Jackson", price: 15.99, year: 1982, genre: "Pop", lengthInMinutes: 42, songs: ["Wanna Be Startin' Somethin'", "Baby Be Mine", "The Girl Is Mine", "Thriller", "Beat It", "Billie Jean", "Human Nature", "P.Y.T. (Pretty Young Thing)", "Lady in My Life"]),
        Album(title: "Hotel California", artist: "Eagles", price: 11.99, year: 1976, genre: "Rock", lengthInMinutes: 43, songs: ["Hotel California", "New Kid in Town", "Life in the Fast Lane", "Wasted Time", "Wasted Time (Reprise)", "Victim of Love", "Pretty Maids All in a Row", "Try and Love Again", "The Last Resort"]),
        Album(title: "Led Zeppelin IV", artist: "Led Zeppelin", price: 13.49, year: 1971, genre: "Hard Rock", lengthInMinutes: 42, songs: ["Black Dog", "Rock and Roll", "The Battle of Evermore", "Stairway to Heaven", "Misty Mountain Hop", "Four Sticks", "Going to California", "When the Levee Breaks"]),
        Album(title: "What's Going On", artist: "Marvin Gaye", price: 10.49, year: 1971, genre: "Soul", lengthInMinutes: 35, songs: ["What's Going On", "What's Happening Brother", "Flyin' High (In the Friendly Sky)", "Save the Children", "God Is Love", "Mercy Mercy Me (The Ecology)", "Right On", "Wholy Holy", "Inner City Blues (Make Me Wanna Holler)"]),
        Album(title: "Nevermind", artist: "Nirvana", price: 11.99, year: 1991, genre: "Grunge", lengthInMinutes: 42, songs: ["Smells Like Teen Spirit", "In Bloom", "Come as You Are", "Breed", "Lithium", "Polly", "Territorial Pissings", "Drain You", "Lounge Act", "Stay Away", "On a Plain", "Something in the Way"]),
        Album(title: "Born to Run", artist: "Bruce Springsteen", price: 9.99, year: 1975, genre: "Rock", lengthInMinutes: 39, songs: ["Thunder Road", "Tenth Avenue Freeze-Out", "Night", "Backstreets", "Born to Run", "She's the One", "Meeting Across the River", "Jungleland"])
    ]
    
    // Keep references to update UI efficiently
    private var albumsGridTemplate: CPGridTemplate?
    
    // Background task to update prices
    private var priceUpdateTask: Task<Void, Never>?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        
        let gridTemplate = self.makeAlbumsGridTemplate()
        
        interfaceController.setRootTemplate(gridTemplate,
                                            animated: true,
                                            completion: nil)
        
        // Start background price updates when CarPlay connects
        startPriceUpdates()
    }

    // MARK: - Albums Grid

    func makeAlbumsGridTemplate() -> CPGridTemplate {
        let buttons = albums.map { album -> CPGridButton in
            let dynamicImage = drawGaugeImage(for: album.price)
            let button = CPGridButton(titleVariants: [album.title],
                                      image: dynamicImage) { [weak self] _ in
                guard let self else { return }
                self.presentInformationTemplate(for: album)
            }
            return button
        }
        let template = CPGridTemplate(title: "Albums", gridButtons: buttons)
        
        albumsGridTemplate = template
        return template
    }
    
    @MainActor
    private func presentInformationTemplate(for album: Album) {
        let artistItem = CPInformationItem(title: "Artist", detail: album.artist)
        let priceItem = CPInformationItem(title: "Price", detail: String(format: "$%.2f", album.price))
        let yearItem = CPInformationItem(title: "Year", detail: "\(album.year)")
        let genreItem = CPInformationItem(title: "Genre", detail: album.genre)
        let lengthItem = CPInformationItem(title: "Length", detail: "\(album.lengthInMinutes) min")

        let tracklistAction = CPTextButton(title: "View Tracklist", textStyle: .normal) { [weak self] _ in
            self?.presentTracklistTemplate(for: album)
        }
        
        let template = CPInformationTemplate(title: album.title,
                                             layout: .twoColumn,
                                             items: [artistItem, priceItem, yearItem, genreItem, lengthItem],
                                             actions: [tracklistAction])
        
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
    
    @MainActor
    private func presentTracklistTemplate(for album: Album) {
        let items = album.songs.enumerated().map { (index, song) -> CPListItem in
            let item = CPListItem(text: song, detailText: "\(index + 1)")
            
            // Add a handler that does nothing to prevent the spinner.
            item.handler = { _, completion in
                // By calling completion immediately, the tap is acknowledged
                // but no further action is taken.
                completion()
            }
            return item
        }
        
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Tracklist: \(album.title)", sections: [section])
        
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
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
                await self.refreshAlbumGridIfVisible()
            }
        }
    }
    
    @MainActor
    private func refreshAlbumGridIfVisible() {
        guard let currentTemplate = albumsGridTemplate else { return }
        // Rebuild buttons with updated dynamic images
        let updatedButtons = albums.map { album -> CPGridButton in
            let dynamicImage = drawGaugeImage(for: album.price)
            let button = CPGridButton(titleVariants: [album.title],
                                      image: dynamicImage) { [weak self] _ in
                guard let self else { return }
                self.presentInformationTemplate(for: album)
            }
            return button
        }
        currentTemplate.updateGridButtons(updatedButtons)
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
