## What a Lambda handler actually is

The **Lambda handler** is **the entry point** of your code.
That’s it. No mysticism.

In Python, it looks like this:

```python
def handler(event, context):
    ...
```

When Lambda runs your function, AWS is effectively doing:

```python
import your_code
your_code.handler(event, context)
```

You don’t call the handler.
You don’t instantiate anything.
AWS calls it for you.

Think of it like `main()` in C, except you’re not allowed to rename the operating system.

---

## The two arguments (they matter)

### `event`

This is **data from the trigger**.

* S3 upload → bucket name + object key
* API Gateway → HTTP request
* EventBridge → event payload
* SQS → batch of messages

Lambda does **zero interpretation**.
It hands you a JSON blob and walks away.

If your code breaks, that’s between you and your debugger.

---

### `context`

This is **runtime metadata**, not business data.

It includes:

* Request ID
* Function name
* Remaining execution time
* Memory limit

Useful for:

* Logging
* Timeouts
* Correlation IDs

Not for:

* Configuration
* Secrets
* Logic decisions

If you’re branching on `context`, you’ve already lost the plot.

---

## How AWS knows which function to call

This line in Lambda configuration:

```
Handler: app.handler
```

Means:

* `app.py` → file
* `handler` → function name

AWS loads the module **once per execution environment**, then reuses it across invocations.

That’s why:

* Global variables persist between calls
* Cold starts exist
* You should initialize clients outside the handler

---

## What actually happens during invocation

Here’s the lifecycle, stripped of marketing.

### 1. Cold start (sometimes)

AWS:

* Spins up a lightweight execution environment
* Mounts your deployment package
* Loads the runtime (Python, Node, etc.)
* Imports your code

This happens **once per container**.

---

### 2. Handler invocation (every time)

AWS:

* Receives an event
* Serializes it to JSON
* Calls your handler function
* Waits for a return or timeout

If you return:

* API Gateway → response is forwarded
* Async trigger → return value is ignored

Lambda doesn’t care what you return unless the trigger does.

---

### 3. Environment reuse

If traffic continues:

* Same environment is reused
* No re-import
* Faster execution

This is why you cache clients globally instead of inside the handler.

---

## How AWS wires all this together (the invisible part)

This is the part people hand-wave. Don’t.

### Event source mapping

When you say:

> “Trigger Lambda on S3 upload”

AWS creates **internal plumbing** that:

* Subscribes Lambda to S3 events
* Validates permissions (`lambda:InvokeFunction`)
* Translates the S3 event into JSON
* Injects it into the Lambda runtime

You never see this wiring because:

* It’s not CloudFormation-visible
* It’s not a network connection
* It’s control-plane orchestration

No sockets. No queues you manage. Just managed glue.

---

### Invocation permissions

S3 cannot invoke Lambda unless:

* Lambda policy explicitly allows it
* AWS validates the source ARN

This is why Terraform has:

```hcl
aws_lambda_permission
```

Without it, the wiring exists but the door is locked.

---

## Why this design exists (important)

Lambda is built on **inversion of control**.

You do NOT:

* Manage servers
* Decide when code runs
* Control the event loop

You DO:

* Write a pure function
* Accept inputs
* Produce outputs or side effects

AWS owns the runtime. You own the logic.

This is why Lambda scales, retries, times out, and fails the way it does.

---

## Mental model you should keep

* Handler = **contract**
* Event = **stimulus**
* Context = **runtime metadata**
* AWS = **scheduler + executor + plumber**

If you think of Lambda as “a function I call,” you’ll fight it.

If you think of it as “a function AWS calls under strict rules,” you’ll build clean systems.

---

## One rule to remember

**Everything outside the handler is setup.
Everything inside the handler is execution.**

If you internalize that, half of Lambda best practices become obvious.

That’s the whole trick.