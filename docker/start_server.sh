#!/bin/bash
bin/rails assets:precompile
bundle exec puma -C config/puma.rb