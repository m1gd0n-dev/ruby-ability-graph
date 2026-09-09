# frozen_string_literal: true -- (n/a, just a marker for editors)

FROM ruby:4.0-slim@sha256:607bf92fa7ecebb4a0c6654b62cb44c48d94b36b6f5a754611ddbbe3dc5b6135

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 app

WORKDIR /app

COPY Gemfile ruby_ability_graph.gemspec ./
COPY lib/ruby_ability_graph/version.rb lib/ruby_ability_graph/version.rb
RUN bundle install

COPY . .

RUN chown -R app:app /app
USER app

ENTRYPOINT ["bundle", "exec"]
CMD ["exe/ruby-ability-graph"]
