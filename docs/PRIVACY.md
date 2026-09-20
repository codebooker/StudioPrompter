# StudioPrompter Companion privacy

StudioPrompter Companion displays a script received from StudioPrompter on a Mac you pair with. Script text, formatting, and playback instructions travel over an encrypted connection on your local network. The companion does not send these to the app developer or a cloud transcription service.

The companion does not request microphone or camera access, include advertising, track you, or send app analytics to the developer. Voice recognition and optional voice commands are processed by the Mac app; the companion does not receive or record microphone audio.

A saved pairing contains the Mac’s displayed name, local discovery identifier, device identifier, and connection credential. It is stored privately on the iPad so you can reconnect after restarting. Choose **Forget Mac** in the companion to remove it. The Mac separately keeps paired-device and removal records so the producer can revoke access and an offline iPad can learn why it was removed. Pairing files are excluded from application backups.

The script received by the companion is held in memory for display; it is not saved as a script library on the iPad. Disconnecting or quitting the companion clears that in-memory copy.

TestFlight and Apple’s operating systems may handle crash reports, tester feedback, or diagnostic information under Apple’s own terms and privacy settings. If you choose to submit feedback, avoid including private scripts or recordings.

Questions and issues: https://github.com/codebooker/StudioPrompter/issues
