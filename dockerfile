# ------------------------------
# Stage 1: Frontend setup
# ------------------------------
FROM node:alpine AS frontend-build

WORKDIR /app/frontend

# Copy static frontend files
COPY frontend/ ./

# Install dependencies (if package.json exists)
RUN npm install && npm run build



# --------------------------
# Stage 2: Backend setup
# --------------------------
FROM node:alpine

WORKDIR /app/backend

# Copy backend files
COPY backend/ ./

# Install backend dependencies
RUN npm install

# Copy frontend static files into backend public folder
COPY --from=frontend-build /app/frontend ./public

# Expose backend port
EXPOSE 5000

# Start backend server
CMD ["node", "server.js"]
