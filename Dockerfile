# frozen_string_literal: true -- (n/a, just a marker for editors)

FROM ruby:4.0.7-slim-trixie@sha256:6c6b7b8c7d750604178aa60c2fa436890cd17c5695bdbd3213db2e4efbf98eb9

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
