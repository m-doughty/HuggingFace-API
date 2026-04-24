use Cro::HTTP::Client;
use JSON::Fast;

unit class HuggingFace::API;

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
