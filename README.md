lifejournal
===========

A small practice project (2014-2017): a clone of OhLife, the "reply to a daily email to keep a journal" service. A Sinatra app sends a prompt email through Mailgun, receives the reply as an inbound Mailgun webhook, and stores the entry in a database.

**Status and stance:** archived. Not maintained since 2017, not run on current Ruby or gem versions, and pull requests are not expected. Use at your own risk.

What it does and stores, so you can judge before borrowing anything:

- Every incoming POST body is saved, and the sender address and entry text are written to the log.
- There is no authentication on the endpoint that triggers the outgoing emails, and Mailgun request signatures are not verified.
- The Mailgun domain, route and app host in `web.rb` (`example.com`) are placeholders. The Mailgun key is read from the `MAILGUN_API_KEY` environment variable.
