# App Review Notes

Paste the text below into the "Notes" field of the App Review Information
section in App Store Connect.

---

TcpButtons is a network utility for developers, home-automation users and
hardware hobbyists. It opens a raw TCP connection to a user-defined host and
port, sends a user-defined UTF-8 payload, and closes the connection. No data is
collected, no account is required, and no external service is contacted.

The app normally talks to a server the user runs themselves, so we have included
a built-in echo server so that the app can be fully tested on the device alone,
with no external hardware or network setup.

To test the app:

1. Launch the app and tap the gear icon in the top right.
2. Under "Echo server", turn on "Local echo server". A green banner appears on
   the main screen confirming it is listening on 127.0.0.1:9000.
3. Tap "Point app at echo server". This sets the destination to 127.0.0.1:9000.
4. Under "Button 1", tap the "Message" field and type any text, for example
   HELLO.
5. Tap "Done" to close settings.
6. Tap "Test connection". The log shows the connection latency in milliseconds.
7. Tap "Button 1". The log shows the message being sent, then "Echo received:
   HELLO", confirming the full round trip.

The local echo server uses the loopback interface only. It is provided as a
demonstration and diagnostic aid and is off by default.
