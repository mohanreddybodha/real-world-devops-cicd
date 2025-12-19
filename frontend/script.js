document.getElementById('feedbackForm').addEventListener('submit', async (e) => {
  e.preventDefault();

  const name = document.getElementById('name').value;
  const email = document.getElementById('email').value;
  const message = document.getElementById('message').value;

  // ✅ Use relative path instead of hardcoding localhost
  const response = await fetch('/feedback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email, message })
  });

  const data = await response.json();

  const feedbackList = document.getElementById('feedbackList');
  const li = document.createElement('li');
  li.textContent = `${data.name} (${data.email}): ${data.message}`;
  feedbackList.prepend(li);

  document.getElementById('feedbackForm').reset();
});
