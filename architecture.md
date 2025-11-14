The application follows an MVVM architecture.

<img width="960" height="540" alt="MVVM architecture" src="https://github.com/user-attachments/assets/846aed4f-4362-4146-a97f-eb9d3e3da19e" />

The primary UI was intended to be CarPlay which is based on UIKit and templates. During the development process - several CarPlay screens were backported to SWiftUI so the same data could be visualized on iPhone or iPad.

There are several View Models that are shared by both versions of the UI (Guages, DTCs, settings, etc). This eliminates some of the duplication and helps organize the code more logically.

Models are used to Store the sensor data used by the various View Models and broker the communications.

The OBD-II communication is handled by the SwiftOBD2 library.
