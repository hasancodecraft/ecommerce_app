# Evira Class Mock Order Server

This local server uses `json-server` for the e-commerce assignment's orders.

## Windows / VS Code

```powershell
cd mock_server
npm install
npm start
```

The server runs at `http://localhost:3001`.

For Android Emulator, Flutter calls `http://10.0.2.2:3001` automatically (see `lib/core/constants/api_constants.dart`).

Endpoints:

- `GET /orders` — order history
- `GET /orders?userId=7` — user's orders
- `POST /orders` — add a new order
- `GET /orders/:id` — an order

The included `db.json` has an empty `orders` list so your own submitted demo orders are easy to find. Keep the server terminal open while using the Flutter application. Without this server, the app saves orders locally and marks them **SAVED LOCALLY**, which is not the same as successful submission to a remote backend.
