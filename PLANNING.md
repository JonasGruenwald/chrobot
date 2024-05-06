# Resources

Protocol Explorer: https://chromedevtools.github.io/devtools-protocol/

Nice guide: https://github.com/aslushnikov/getting-started-with-cdp/blob/master/README.md

# Experiment

```json
{"id" : 1, "method": "Browser.getVersion"}
```

# Components

## Generated Protocol Binding Modules

Typesafe primitives that can be used to interact with the protocol.

Includes:

- Types representing the types, commands and events of each protocol domain
- Functions for serializing properties into JSON for sending via the protocol and vice versa


## Browser Module

Utilities for launching a browser instance with a remote debugging port and managing its lifetime.

## Connection Module

Utilities for communicating with the launched browser via the protocol bindings

## Lib core 

High level functions that use the above modules internally to provide easy access to common automation tasks


# Idea

A high level browser automation framework, offering a typed API to the chrome devtools protocol.

Should at least offer the following:

- Launching a browser instance with the required flags and managing it
- Creating and managing a websocket connection to the devtools protocol
- Encoding and decoding messages to the protocol
