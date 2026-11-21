# gb10-stack.sh

A Bash script that deploys and manages a **local LLM stack for log analysis** on a Dell Pro Max with GB10 (NVIDIA DGX OS): **vLLM** for inference and **LiteLLM** as the single OpenAI-compatible endpoint, with Docker Compose.

![Bash](https://img.shields.io/badge/Bash-5%2B-blue)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Part of the blog series [Dell Pro Max GB10 – Building a local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/).

---

## Architecture

```
clients (automation platform, scripts)
        │  http://<host>:4000/v1   model: "log-analyzer"
        ▼
   LiteLLM  ── one endpoint, one API key, model aliases
        │  http://vllm:8000/v1 (internal Docker network)
        ▼
    vLLM    ── NVIDIA NGC container, GPU, model cache in /srv/ai/models
```

Clients ask for the alias `log-analyzer`, never the backend model name, so the model can be swapped without touching any client.

---

## Why this model

The model and container come from **NVIDIA's validated DGX Spark 128 GB recipe**:

| Setting | Value | Why it matters for log analysis |
|---------|-------|---------------------------------|
| Container | `nvcr.io/nvidia/vllm:26.10.pre1-py3` | Official NGC image, built for the GB10 |
| Model | `nvidia/Qwen3.8-27B-NVFP4` | Recommended single-Spark model, NVFP4 quantized |
| Context | 262,144 tokens | Large log excerpts fit in one request |
| Speculative decoding | DFlash draft model | Faster generation on a bandwidth-bound box |
| Structured output | JSON schema via `response_format` | Results the automation platform can parse |
| Prefix caching | on | The same system prompt is reused on every call |

The launch flags are kept exactly as in NVIDIA's recipe – they are tuned to work together on this hardware.

---

## Requirements

- [`gb10-prepare.sh`](../gb10-prepare/) has been run: `/srv/ai`, the `aiops` group and `stack/.env` with `LITELLM_MASTER_KEY`
- Your user is in `aiops` and `docker` (log out and in after `gb10-prepare.sh`)
- GPU access for containers works: `docker run --rm --gpus all ubuntu nvidia-smi`
- Internet access to nvcr.io, ghcr.io and huggingface.co for the first start
- Optional: `HF_TOKEN` in `stack/.env` if a gated model is used later

---

## Usage

```bash
bash gb10-stack.sh deploy     # write compose.yaml + LiteLLM config (only if missing), pull, start
bash gb10-stack.sh logs       # follow vLLM - ready at "Application startup complete"
bash gb10-stack.sh status     # containers, health, models
bash gb10-stack.sh test       # log-analysis smoke test with JSON schema output
bash gb10-stack.sh down       # stop the stack
bash gb10-stack.sh deploy --force   # overwrite generated files (backups are kept)
```

The **first start takes a long time**: the model and draft model are downloaded into `/srv/ai/models`, and vLLM runs autotuning and compilation. LiteLLM waits until vLLM reports healthy.

Files written to `/srv/ai/stack`:

- `compose.yaml`
- `litellm/config.yaml`

Existing files are never overwritten without `--force`, so manual changes are kept.

---

## Calling it

```bash
curl http://<host>:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"log-analyzer","messages":[{"role":"user","content":"Analyse: ..."}]}'
```

The `test` command shows a complete example with a JSON schema for findings (severity, component, issue, likely cause, next step).

---

## Parameters

At the top of the script: `AI_ROOT`, `VLLM_IMAGE`, `MODEL`, `DRAFT_MODEL`, `MAX_MODEL_LEN`, `GPU_MEM_UTIL`, `LITELLM_IMAGE`, `LITELLM_PORT`, `MODEL_ALIAS`.

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
