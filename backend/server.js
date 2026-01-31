const express = require('express');
const cors = require('cors');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 5000;
const BASE_PATH = '/app';

app.use(cors());
app.use(express.json());

// Serve frontend static files
app.use(BASE_PATH, express.static(path.join(__dirname, 'public')));

// In-memory feedback store
let feedbacks = [];

// API endpoints
app.post(`${BASE_PATH}/feedback`, (req, res) => {
  const { name, email, message } = req.body;
  const entry = { name, email, message };
  feedbacks.push(entry);
  res.json(entry);
});

app.get(`${BASE_PATH}/feedback`, (req, res) => {
  res.json(feedbacks);
});

// SPA fallback
app.get(`${BASE_PATH}/*`, (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});