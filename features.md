The application exercises several features...

* SwiftUI and UIKit/CarPlay screens.
* MVVM architecture with shared View Models.
* Tabbed Navigation.
* Settings saved via @AppStorage.
* Facility to export logs via JSON APIs.
* Dynamic support for Metric/Imperial units.
* Support for Bluetooth, Wifi and demo mode OBDII adapters.

The SwiftOBD2 library was a good start for abstracting OBD2 communications but needed significant work to fix bugs and extend capabilities to meet the needs of this app.
The demo mode was extended to provide more lifelike values for the sensors that change over time.
The app makes heavily used of the @Published/Subscription semantics to update the screens in real-time in response to changing data.
The app supports a full list of OBD2 mode1 sensors with expected ranges and data types.
The app includes a full list of DTCs with explanation, cause and corrections.
