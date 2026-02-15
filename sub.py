
import zenoh
import time


def listener(sample):
    print(
        f"Received {sample.kind} ('{sample.key_expr}': '{sample.payload.to_string()}')")


if __name__ == "__main__":

    config = zenoh.Config()
    config.insert_json5("connect/endpoints", '["tcp/localhost:7447"]')
    with zenoh.open(config) as session:

        sub = session.declare_subscriber('**', listener)
        block = True
        while block:
            try:
                time.sleep(1)
            except Exception as e:
                print(f"Error declaring subscriber: {e}")
            except KeyboardInterrupt:
                print("Shutting down subscriber...")
                block = False
