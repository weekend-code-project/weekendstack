# AI Services Quick Reference

Quick commands and endpoints for integrating SearXNG, Ollama, and N8N.

## 🚀 Quick Start Commands

```bash
# Start all AI services
docker compose --profile ai --profile automation up -d

# Start only search services
docker compose up -d searxng

# Start only automation
docker compose --profile automation up -d

# Check service status
docker compose ps
```

## 🌐 Service URLs

| Service | Local URL | Internal Docker URL |
|---------|-----------|-------------------|
| SearXNG | http://localhost:4000 | http://searxng:8080 |
| Open WebUI | http://localhost:3000 | http://open-webui:8080 |
| N8N | http://localhost:5678 | http://n8n:5678 |
| Ollama | http://localhost:11434 | http://host.docker.internal:11434 |

## 🔗 API Endpoints

### SearXNG API
```bash
# Basic search
curl "http://localhost:4000/search?q=docker&format=json"

# Search specific engines
curl "http://localhost:4000/search?q=kubernetes&format=json&engines=google,github"

# Autocomplete
curl "http://localhost:4000/autocompleter?q=docker"

# Get configuration
curl "http://localhost:4000/config"
```

### Ollama API
```bash
# List models
curl http://localhost:11434/api/tags

# Generate text
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Explain Docker containers",
  "stream": false
}'

# Chat completion
curl http://localhost:11434/api/chat -d '{
  "model": "llama3.2",
  "messages": [
    {"role": "user", "content": "What is Kubernetes?"}
  ]
}'
```

### N8N Webhooks
```bash
# Trigger research workflow
curl -X POST http://localhost:5678/webhook/research-assistant \
  -H "Content-Type: application/json" \
  -d '{"query": "latest AI developments"}'

# Content monitoring
curl -X POST http://localhost:5678/webhook/content-monitor \
  -H "Content-Type: application/json" \
  -d '{"topic": "Docker security", "frequency": "daily"}'
```

## 🔧 Environment Variables

```bash
# Core AI Services
AI_CHAT_PROFILE=ai
AI_SEARCH_PROFILE=ai
AUTOMATION_N8N_PROFILE=automation

# SearXNG Configuration
SEARXNG_PORT=4000
SEARXNG_SECRET=your-secret-key
SEARXNG_TRAEFIK_ENABLE=false

# Open WebUI Integration
OPENWEBUI_RAG_WEB_SEARCH_ENGINE=searxng
OPENWEBUI_SEARXNG_URL=http://searxng:8080

# Ollama Connection
OLLAMA_HOST=http://host.docker.internal:11434
```

## 🛠️ Troubleshooting

```bash
# Check logs
docker compose logs searxng
docker compose logs open-webui
docker compose logs n8n

# Restart services
docker compose restart searxng
docker compose restart open-webui
docker compose restart n8n

# Test connectivity
docker compose exec open-webui ping searxng
docker compose exec n8n curl http://searxng:8080/search?q=test

# Verify Ollama
ollama list
curl http://localhost:11434/api/tags
```

## 📋 Common Workflows

### 1. Research and Summarize
```bash
# 1. Search via SearXNG
RESULTS=$(curl -s "http://localhost:4000/search?q=docker%20security&format=json")

# 2. Process with Ollama
curl http://localhost:11434/api/generate -d "{
  \"model\": \"llama3.2\",
  \"prompt\": \"Summarize these search results: ${RESULTS}\",
  \"stream\": false
}"
```

### 2. Automated Content Pipeline
```bash
# Trigger N8N workflow
curl -X POST http://localhost:5678/webhook/content-pipeline \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "Kubernetes best practices",
    "format": "blog_post",
    "length": "medium"
  }'
```

### 3. Real-time Search Integration
```javascript
// JavaScript example for web applications
async function searchAndAnalyze(query) {
  // Search via SearXNG
  const searchResponse = await fetch(
    `http://localhost:4000/search?q=${encodeURIComponent(query)}&format=json`
  );
  const searchResults = await searchResponse.json();
  
  // Analyze with Ollama
  const analysisResponse = await fetch('http://localhost:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'llama3.2',
      prompt: `Analyze these search results: ${JSON.stringify(searchResults.results.slice(0, 3))}`,
      stream: false
    })
  });
  
  return await analysisResponse.json();
}
```

## 🎯 Use Case Templates

### Research Assistant
```json
{
  "webhook": "/webhook/research",
  "method": "POST",
  "body": {
    "query": "your research topic",
    "depth": "comprehensive|summary|quick",
    "sources": ["google", "bing", "duckduckgo", "github"]
  }
}
```

### Content Monitor
```json
{
  "webhook": "/webhook/monitor",
  "method": "POST", 
  "body": {
    "keywords": ["keyword1", "keyword2"],
    "frequency": "hourly|daily|weekly",
    "notification": "email|webhook|slack"
  }
}
```

### SEO Analyzer
```json
{
  "webhook": "/webhook/seo-analyze",
  "method": "POST",
  "body": {
    "target_keyword": "your keyword",
    "competitor_urls": ["url1", "url2"],
    "analysis_type": "comprehensive|quick"
  }
}
```
