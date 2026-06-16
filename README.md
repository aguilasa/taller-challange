# AI-First Fullstack Challenge — Java + React

Small payments admin app. Backend: Spring Boot. Frontend: React + Vite.

## Scenario
Customers are reporting two issues:
1. Some are seeing duplicate charges for the same purchase.
2. Security flagged something in the charge flow and support search UI.

There may be more. Find what you can.

## Run backend

```bash
cd backend
mvn spring-boot:run
```

Backend listens on `http://localhost:8080`.

## Run frontend

```bash
cd frontend
npm install
npm run dev
```

Frontend listens on `http://localhost:5173`.

## Tests

```bash
cd backend && mvn test
cd frontend && npm test
```

The existing tests are happy-path tests. They pass, but they do not prove the app is correct.
