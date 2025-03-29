# syntax=docker/dockerfile:1
# check=error=true

# Set the Ruby version as an argument (it will be used to fetch the base image)
ARG RUBY_VERSION=3.3.6

# Use the official Ruby slim image as a base
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Set the working directory for the Rails app
WORKDIR /rails

# Install base dependencies (make sure you have necessary permissions)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Set the Rails environment to production and configure Bundler
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Build stage to install the application dependencies
FROM base AS build

# Install additional dependencies needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy the Gemfile and Gemfile.lock to the working directory
COPY Gemfile Gemfile.lock ./

# Install the application gems
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy the entire application code to the container
COPY . .

# Precompile Bootsnap to speed up Rails boot time
RUN bundle exec bootsnap precompile app/ lib/

# Ensure that binfiles are executable and fix line endings for Linux
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Final stage for production-ready app image
FROM base

# Copy built artifacts (gems, app code) from the build stage
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Create a non-root user for security purposes
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp

# Switch to the non-root user
USER 1000:1000

# Set the entrypoint to prepare the database
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Expose port 80 (change this if you're using a different port in production)
EXPOSE 80

# Start the Rails server using the `thrust` script, this can be overwritten at runtime
CMD ["./bin/thrust", "./bin/rails", "server"]
