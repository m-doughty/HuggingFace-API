use Cro::HTTP::Client;
use JSON::Fast;

unit class HuggingFace::API;

#|( Pull the chat template body out of a parsed tokenizer_config.json
    payload. Tokenizer configs ship the template in two shapes:

    =item 1. C<chat_template> as a string (most models — Mistral, Llama,
    Qwen).

    =item 2. C<chat_template> as a list of C<{name, template}> hashes
    (Cohere Command A and other multi-template repos). When this
    happens we prefer the entry named C<default>; failing that we
    take the first entry.

    Returns C<Str> (undefined) when the config has no template field
    at all, or when the array form is structurally malformed. Empty
    strings are returned as-is — an empty C<chat_template> is a
    deliberate "this model has no chat template" signal in some
    repos and we don't conflate it with absence. )
sub extract-chat-template-from-config(Str:D $json --> Str) is export {
	my %config = try { from-json($json) } // %();
	return Str unless %config<chat_template>:exists;

	my $ct = %config<chat_template>;
	given $ct {
		when Str {
			return $_;
		}
		when Positional {
			my $default = .first({
				$_ ~~ Associative
					&& ($_<name>:exists)
					&& $_<name> eq 'default'
			});
			return $default<template>.Str if $default.defined && $default<template>.defined;

			my $first = .[0];
			return $first<template>.Str
				if $first ~~ Associative && $first<template>.defined;
		}
	}
	Str;
}

has Str:D $.base-url = 'https://huggingface.co';
has Str $.api-key;

method !client(--> Cro::HTTP::Client:D) {
	Cro::HTTP::Client.new(
		:headers(self!headers),
		:http<1.1>,
	);
}

method !headers(--> List) {
	my @h;
	@h.push(Authorization => "Bearer $!api-key") if $!api-key.defined;
	@h;
}

method search(Str:D $query, Int:D :$limit = 10 --> List) {
	my $url = "$!base-url/api/models?search=$query&limit=$limit";
	my $resp = await self!client.get($url);
	my $json = await $resp.body-text;
	my @models = from-json($json).list;
	@models.map(-> %m {
		%(
			id          => %m<modelId> // %m<id> // '',
			author      => %m<author> // '',
			downloads   => %m<downloads> // 0,
			likes       => %m<likes> // 0,
			pipeline    => %m<pipeline_tag> // '',
			tags        => (%m<tags> // []).list,
			description => %m<description> // '',
		)
	}).list;
}

#| Download any file from a HuggingFace repo as text. For binary
#| files (ONNX weights, safetensors, tarballs) use get-file-blob /
#| get-file-to-file — text decode can corrupt non-UTF8 bytes.
#|
#| `$revision` accepts a branch name ('main'), tag ('v1.0'), or
#| commit SHA ('d22488bc83be87678f12eee8a3f65a65de94ef85'). For
#| reproducible installs pin a SHA.
method get-file(Str:D $model-id, Str:D $filename,
                Str:D :$revision = 'main' --> Str:D) {
	my $url = "$!base-url/$model-id/resolve/$revision/$filename";
	my $resp = await self!client.get($url);
	await $resp.body-text;
}

#| Download any file from a HuggingFace repo as a Blob. Safe for
#| binary artefacts (model.onnx, safetensors, tarballs).
method get-file-blob(Str:D $model-id, Str:D $filename,
                    Str:D :$revision = 'main' --> Blob:D) {
	my $url = "$!base-url/$model-id/resolve/$revision/$filename";
	my $resp = await self!client.get($url);
	await $resp.body-blob;
}

#| Download a file and write it to disk. Binary-safe; used for
#| large artefacts where holding the whole body in memory is
#| wasteful. Returns the output path for chaining.
method get-file-to-file(Str:D $model-id, Str:D $filename,
                        IO::Path:D $output,
                        Str:D :$revision = 'main' --> IO::Path:D) {
	my Blob:D $body = self.get-file-blob($model-id, $filename, :$revision);
	$output.spurt($body, :bin);
	$output;
}

method get-tokenizer(Str:D $model-id,
                     Str :$filename = 'tokenizer.json',
                     Str:D :$revision = 'main' --> Str:D) {
	self.get-file($model-id, $filename, :$revision);
}

method get-tokenizer-to-file(Str:D $model-id, IO::Path:D $output,
                             Str :$filename = 'tokenizer.json',
                             Str:D :$revision = 'main' --> IO::Path:D) {
	my Str:D $json = self.get-tokenizer($model-id, :$filename, :$revision);
	$output.spurt($json);
	$output;
}

method get-tokenizer-config(Str:D $model-id,
                            Str:D :$revision = 'main' --> Str:D) {
	self.get-file($model-id, 'tokenizer_config.json', :$revision);
}

method get-tokenizer-config-to-file(Str:D $model-id, IO::Path:D $output,
                                    Str:D :$revision = 'main' --> IO::Path:D) {
	my Str:D $json = self.get-tokenizer-config($model-id, :$revision);
	$output.spurt($json);
	$output;
}

#|( Fetch a model's Jinja chat template, trying C<chat_template.jinja>
    first and falling back to extracting C<chat_template> from
    C<tokenizer_config.json> when the standalone file isn't present.

    Modern HF uploads (post mid-2024) ship the Jinja source as a
    standalone C<chat_template.jinja> file alongside the tokenizer;
    older repos embed it as a string field on the tokenizer config.
    A small minority (Cohere Command A) use a list form on the
    config — see L<extract-chat-template-from-config> for the shape.

    Returns the template body as C<Str>, or C<Str> (undefined) when
    the model has neither a standalone Jinja file nor an embedded
    template (typical for base models / classifiers). Network and
    auth errors propagate; only HTTP 404 is treated as "absent". )
method get-chat-template(Str:D $model-id,
                         Str:D :$revision = 'main' --> Str) {
	my $jinja = self!try-get-file($model-id, 'chat_template.jinja', :$revision);
	return $jinja if $jinja.defined;

	my $config-json = self!try-get-file($model-id, 'tokenizer_config.json', :$revision);
	return Str unless $config-json.defined;

	extract-chat-template-from-config($config-json);
}

#|( Fetch and write a model's Jinja chat template to disk. See
    L<get-chat-template> for source-resolution semantics.

    Returns the output C<IO::Path> on success; returns C<IO::Path>
    (undefined) when the model has no chat template, leaving the
    target path untouched. The file is written atomically as a
    plain string (no JSON wrapping) regardless of which source it
    was extracted from, so downstream consumers can slurp it
    directly into a Jinja renderer. )
method get-chat-template-to-file(Str:D $model-id, IO::Path:D $output,
                                 Str:D :$revision = 'main' --> IO::Path) {
	my $template = self.get-chat-template($model-id, :$revision);
	return IO::Path unless $template.defined;
	$output.spurt($template);
	$output;
}

#|( Fetch a single file, returning C<Str> on HTTP 404 instead of
    propagating. Used by L<get-chat-template> to probe candidate
    sources without forcing the caller to wrap each call in a try
    block. Other HTTP errors and network failures still throw. )
method !try-get-file(Str:D $model-id, Str:D $filename,
                     Str:D :$revision = 'main' --> Str) {
	my $url = "$!base-url/$model-id/resolve/$revision/$filename";
	my $body;
	try {
		my $resp = await self!client.get($url);
		$body = await $resp.body-text;
		CATCH {
			when X::Cro::HTTP::Error::Client {
				return Str if .response.status == 404;
				.rethrow;
			}
		}
	}
	$body;
}
