"""PyWorker configuration for DeepSeek-OCR-2 serverless endpoint on vast.ai."""

from vastai import Worker, WorkerConfig, HandlerConfig, LogActionConfig, BenchmarkConfig

MODEL_SERVER_URL = "http://127.0.0.1"
MODEL_SERVER_PORT = 18000
MODEL_LOG_FILE = "/var/log/portal/ocr_server.log"
MODEL_HEALTHCHECK_ENDPOINT = "/health"

MODEL_LOAD_LOG_MSG = [
    "Application startup complete.",
]

MODEL_ERROR_LOG_MSGS = [
    "Traceback (most recent call last):",
    "RuntimeError:",
    "CUDA out of memory",
]

MODEL_INFO_LOG_MSGS = [
    "Loading model:",
    "Model loaded in",
]


def request_parser(request):
    data = request
    if request.get("input") is not None:
        data = request.get("input")
    return data


def benchmark_generator() -> dict:
    """Generate a minimal benchmark request (small base64 image)."""
    import base64
    # 1x1 white PNG
    tiny_png = base64.b64encode(
        b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01'
        b'\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00'
        b'\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00'
        b'\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82'
    ).decode()
    return {
        "image_base64": tiny_png,
        "prompt": "<image>\n<|grounding|>Convert the document to markdown. ",
        "base_size": 1024,
        "image_size": 768,
        "crop_mode": True,
    }


worker_config = WorkerConfig(
    model_server_url=MODEL_SERVER_URL,
    model_server_port=MODEL_SERVER_PORT,
    model_log_file=MODEL_LOG_FILE,
    model_healthcheck_url=MODEL_HEALTHCHECK_ENDPOINT,
    handlers=[
        HandlerConfig(
            route="/ocr",
            workload_calculator=lambda data: 1,
            allow_parallel_requests=False,
            request_parser=request_parser,
            max_queue_time=600.0,
            benchmark_config=BenchmarkConfig(
                generator=benchmark_generator,
                concurrency=1,
                runs=1,
            ),
        ),
        HandlerConfig(
            route="/health",
            workload_calculator=lambda data: 0,
            allow_parallel_requests=True,
            request_parser=request_parser,
            max_queue_time=10.0,
        ),
    ],
    log_action_config=LogActionConfig(
        on_load=MODEL_LOAD_LOG_MSG,
        on_error=MODEL_ERROR_LOG_MSGS,
        on_info=MODEL_INFO_LOG_MSGS,
    ),
)

Worker(worker_config).run()
