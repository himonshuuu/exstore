# ExStore

ExStore is a simple in-memory key-value store written in Elixir.

It supports the following operations:

- `SET key value [ttl]`: Set the value of `key` to `value` with an optional time-to-live (TTL) in seconds.
- `GET key`: Retrieve the value associated with `key`.
- `DEL key`: Delete the key-value pair associated with `key`.
- `TTL key`: Retrieve the TTL associated with `key`, or `-2` if the key does not exist or has no TTL.

This library is intended for testing and development purposes, and is not suitable for production use.

## Usage with Netcat

You can interact with ExStore using a simple TCP client like `netcat`. Below are some examples of how to use it:

1. **Start the ExStore server:**

   Ensure that the ExStore server is running on the default port `6380`.

2. **Connect to the server using netcat:**

   ```bash
   nc localhost 6380
   ```

3. **Execute commands:**

   - To set a key with an optional TTL:
     ```
     SET key value 10
     ```

   - To retrieve a value:
     ```
     GET key
     ```

   - To delete a key:
     ```
     DEL key
     ```

   - To get the TTL of a key:
     ```
     TTL key
     ```

