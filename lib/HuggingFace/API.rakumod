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

method get-tokenizer(Str:D $model-id, Str :$filename = 'tokenizer.json' --> Str:D) {
	my $url = "$!base-url/$model-id/resolve/main/$filename";
	my $resp = await self!client.get($url);
	await $resp.body-text;
}

method get-tokenizer-to-file(Str:D $model-id, IO::Path:D $output, Str :$filename = 'tokenizer.json' --> IO::Path:D) {
	my Str:D $json = self.get-tokenizer($model-id, :$filename);
	$output.spurt($json);
	$output;
}
