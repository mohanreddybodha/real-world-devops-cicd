const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 5000;

// Enable CORS and JSON parsing
app.use(cors());
app.use(express.json());

// ✅ Serve frontend static files
app.use(express.static(path.join(__dirname, 'public')));

// In-memory feedback store
let feedbacks = [];

// ✅ API endpoint to receive feedback
app.post('/feedback', (req, res) => {
  const { name, email, message } = req.body;
  const entry = { name, email, message };
  feedbacks.push(entry);
  res.json(entry);
});

// ✅ API endpoint to retrieve feedback
app.get('/feedback', (req, res) => {
  res.json(feedbacks);
});

// ✅ Serve frontend on all other routes (SPA fallback)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ✅ Start server
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});