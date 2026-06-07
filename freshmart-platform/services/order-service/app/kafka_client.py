"""
Kafka event publisher — gracefully degraded when Kafka is unavailable.
In Phase 2 (local dev), KAFKA_ENABLED=false and no events are published.
In Phase 3+ (Kind/EKS), set KAFKA_ENABLED=true to activate.
"""
import json
import logging
from typing import Any

logger = logging.getLogger(__name__)

_producer = None


async def init_producer(bootstrap_servers: str) -> None:
    global _producer
    try:
        from aiokafka import AIOKafkaProducer
        _producer = AIOKafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        )
        await _producer.start()
        logger.info("Kafka producer connected to %s", bootstrap_servers)
    except Exception as e:
        logger.warning("Kafka unavailable — events will be skipped: %s", e)
        _producer = None


async def close_producer() -> None:
    global _producer
    if _producer:
        await _producer.stop()
        _producer = None


async def publish(topic: str, payload: Any) -> None:
    """Best-effort publish — never raises, so service continues on Kafka failure."""
    if _producer is None:
        logger.debug("Kafka not connected, skipping event: topic=%s", topic)
        return
    try:
        await _producer.send_and_wait(topic, payload)
        logger.info("Published to %s: %s", topic, payload)
    except Exception as e:
        logger.warning("Kafka publish failed (topic=%s): %s", topic, e)
