# Fixit Lanka - Supervisor App

The Fixit Lanka Supervisor App is designated for administrative and supervisory roles within the Fixit Lanka ecosystem. It empowers supervisors to oversee incoming job requests, manage worker assignments, and maintain quality control across the service platform.

## Features

- **Supervisor Login**: Secure role-based authentication.
- **Dashboard**: Overview of system statistics and active jobs.
- **Job Management**: Review, approve, or decline user job requests.
- **Worker Assignment**: Dispatch available workers to approved jobs efficiently.
- **Real-time Synchronization**: Instant updates reflecting changes made across the ecosystem via Firebase.
- **Push Notifications**: Receive updates about new reports and worker statuses.

## Technologies Used

- **Framework**: Flutter
- **Backend/Database**: Firebase (Authentication, Firestore Database)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ThEVI22/Fixit_Lanka-Supervisorapp.git
   ```
2. Navigate to the project directory:
   ```bash
   cd Fixit_Lanka-Supervisorapp
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Setup

Please ensure Firebase is configured setup correctly. The required configuration files (`google-services.json` for Android and `GoogleService-Info.plist` for iOS) need to be included.

---

> This project is a part of the CC Final Project submission.
