# Teachers Fee Management System

A Flutter-based tuition fee management application designed to help teachers organise student batches, manage monthly tuition-fee deadlines, and send fee reminders to students.

> **Project status:** Update this section before publishing (for example: `In development`, `Testing`, or `Completed`).

## Overview

Teachers Fee Management System is a mobile application with separate access for administrators, teachers, and students. Teachers can create batches and associate students with the relevant batch. When a batch's monthly fee deadline is reached, students associated with that batch receive a fee reminder notification.

The application does not currently include an online payment gateway. Any extra or manually handled payment is managed by the teacher.

## User Roles

### Admin
- Access to the administrator area inside the mobile application.
- Administrative features should be documented here once the exact permissions and workflows are finalised.

### Teacher
- Register and sign in through the teacher access flow.
- Create and manage batches.
- Set the tuition-fee deadline for a batch.
- Manage students associated with a batch.
- Handle additional or manually recorded payments, where applicable.

### Student
- Register and sign in through the student access flow.
- Be associated with the relevant teacher-created batch.
- Receive fee reminder notifications for the batch they belong to.

## Main Features

- Separate Admin, Teacher, and Student access.
- User registration and login.
- Teacher-created student batches.
- Student-to-batch association.
- Monthly tuition-fee deadline management.
- Fee reminder notifications for students in the relevant batch.
- Teacher-managed handling of additional/manual payments.
- JWT-based authentication.

## Technology Stack

| Layer | Technology |
|---|---|
| Mobile application | Flutter |
| Backend | Node.js |
| Database | MySQL |
| Authentication | JSON Web Tokens (JWT) |

## Application Workflow

1. A teacher signs in and creates a batch.
2. The teacher configures the batch's tuition-fee deadline.
3. Students sign in and are associated with the relevant batch.
4. When the configured fee deadline is reached, the students in that batch receive a fee reminder notification.
5. Any extra or manually handled payment is managed by the teacher; the app does not currently process online payments.

## Repository Structure

The repository is intended to contain the mobile application and backend in one place. Adjust the folder names below if your actual project uses a different structure.

```text
teachers-fee-management-system/
├── mobile-app/          # Flutter application source code
│   ├── lib/
│   ├── assets/           # Include if used by the project
│   └── pubspec.yaml
├── backend/              # Node.js backend source code
│   ├── package.json
│   └── ...
├── docs/
│   └── screenshots/      # Optional application screenshots
├── README.md
└── .gitignore
```

## Getting Started

These are the general setup steps. The exact environment-variable names and backend start command must match the implementation in this repository.

### Requirements

- Flutter SDK (compatible with the version used by the project)
- Dart SDK (provided with Flutter)
- Node.js and npm
- MySQL Server
- Android Studio or another supported Flutter development environment

### 1. Clone the repository

```bash
git clone https://github.com/ranasaidia32-ai/teachers-fee-management-system.git
cd teachers-fee-management-system
```

### 2. Set up the backend

```bash
cd backend
npm install
```

Create a local environment file using the variable names expected by the backend code. Configure the MySQL connection and JWT secret locally. **Do not commit your real `.env` file, database password, JWT secret, or any other credentials.**

Start the backend using the command defined in the `scripts` section of `backend/package.json`.

### 3. Set up the mobile application

Open a second terminal from the repository root and run:

```bash
cd mobile-app
flutter pub get
flutter run
```

Configure the app's API base URL to point to your running backend, using the configuration method already present in the project.

## Screenshots

Add genuine screenshots of your own application in `docs/screenshots/`, then embed them here. Do not add sample images that do not represent the actual app.

Example (replace the path with a real screenshot file):

```markdown
![Teacher dashboard](docs/screenshots/teacher-dashboard.png)
```

## Security Notes

- Authentication uses JWT, as implemented in the project.
- Keep credentials and secrets in local environment configuration; never publish them in source code or screenshots.
- Remove real student names, phone numbers, payment details, and other personal information from demo screenshots and sample data.
- Do not describe the application as security-audited unless an independent security audit has actually been completed.

## Payment Scope

This application does not currently provide online payment processing or a payment gateway. Additional or manually handled payments are managed by the teacher.

## Current Limitations and Future Improvements

Update this section to reflect the actual roadmap. Potential future improvements (only include items you genuinely plan to build) may include:

- Online payment gateway integration.
- Exportable fee reports and receipts.
- Additional notification preferences.
- More detailed admin reporting.

## Author

**Rana**  
GitHub: [@ranasaidia32-ai](https://github.com/ranasaidia32-ai)

## Disclaimer

This repository is provided for project demonstration and development purposes. Do not use real student or payment data in a public demo environment.
