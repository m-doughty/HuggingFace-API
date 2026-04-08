[![Actions Status](https://github.com/m-doughty/HuggingFace-API/actions/workflows/test.yml/badge.svg)](https://github.com/m-doughty/HuggingFace-API/actions)

NAME
====

HuggingFace::API - Raku client for the HuggingFace API

SYNOPSIS
========

```raku
use HuggingFace::API;

my $hf = HuggingFace::API.new;

# Search for models
my @models = $hf.search('mistral', :limit(5));
for @models -> %m {
    say "%m<id> — %m<downloads> downloads";
}

# Download a tokenizer
my $json = $hf.get-tokenizer('mistralai/Mistral-7B-v0.1');

# Save tokenizer to file
$hf.get-tokenizer-to-file('mistralai/Mistral-7B-v0.1', 'tokenizer.json'.IO);

# With API key (for gated models)
my $hf-auth = HuggingFace::API.new(:api-key('hf_...'));
my $json = $hf-auth.get-tokenizer('meta-llama/Llama-3-8B');
```

DESCRIPTION
===========

HuggingFace::API provides a Raku client for the HuggingFace API. Currently supports model search and tokenizer downloads.

Methods
-------

```raku
my $hf = HuggingFace::API.new(
    :api-key('hf_...'),     # Optional, for gated models
);

# Search models by prefix
$hf.search(Str $query, Int :$limit = 10 --> List)
    # Returns list of hashes with: id, author, downloads, likes, pipeline, tags, description

# Download tokenizer JSON as string
$hf.get-tokenizer(Str $model-id, Str :$filename = 'tokenizer.json' --> Str)

# Download tokenizer JSON to file
$hf.get-tokenizer-to-file(Str $model-id, IO::Path $output, Str :$filename = 'tokenizer.json' --> IO::Path)
```

AUTHOR
======

Matt Doughty <matt@apogee.guru>

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

