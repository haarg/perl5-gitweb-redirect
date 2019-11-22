use strict;
use warnings;

use Plack::Request;
use WWW::Form::UrlEncoded qw(build_urlencoded_utf8);
use HTTP::Tiny;
use JSON::MaybeXS qw(decode_json);

my $org_root = 'https://github.com/Perl';

sub get_url {
  my $url = join '/', @_;
  return
    $url =~ m{\A\w+:} ? $url
    : $org_root . ($url ? "/$url" : "");
}

sub final {
  my $url = get_url(@_);
  return [ 301, [ Location => $url ], [ 'Moved' ] ];
}

sub near {
  my $url = get_url(@_);
  return [ 302, [ Location => $url ], [ 'Moved' ] ];
}

sub branch {
  my ($def, @path) = @_;
  my $branch = join('/', @path);
  undef $branch if $branch eq 'HEAD';
  $branch ||= $def;
  $branch =~ s{\Arefs/(?:heads|tags)/}{};
  $branch =~ s{\.\.\.refs/(?:heads|tags)/}{};
  return $branch;
}

sub branch_path {
  my ($def, @path) = @_;
  my ($branch, $file) = split ':', join('/', @path), 2;
  $file =~ s{\A/}{};
  return (branch($def, $branch), $file);
}

my %actions = (
  tags => 'tags',
  heads => 'branches',
  committers => 'https://github.com/orgs/Perl/teams/perl-core-dev',
  'atom' => 'commits.atom',
  'rss' => 'commits.atom',
);
my %branch_actions = (
  log => 'commits',
  shortlog => 'commits',
  commit => 'commit',
  commitdiff => 'commit',
);

my %path_actions = (
  blame => 'blame',
  blame_incremental => 'blame',
  blob => 'blob',
  blob_plain => 'raw',
  history => 'commits',
  tree => 'tree',
);

my $ua = HTTP::Tiny->new;
my %tags;

sub {
  my ($env) = @_;
  my $req = Plack::Request->new($env);

  my $path = $req->path_info;
  my $params = $req->query_parameters;

  $path =~ s{//+}{/};
  my @path = split m{/}, $path;
  shift @path
    while @path && $path[0] eq '';
  pop @path
    while @path && $path[-1] eq '';

  if (!@path) {
    return final;
  }
  my $repo = shift @path;
  $repo =~ s/\.git\z//;

  my $action = shift @path;
  if (exists $params->{a}) {
    $action = $params->{a};
  }

  my $def_branch = $repo eq 'perl5' ? 'blead' : 'master';
  if (!defined $action) {
    return final $repo;
  }

  my $new_action;
  if ($action eq 'search') {
    my $type = $params->{st};
    my $search = $params->{s};
    my $where = $params->{h};
    my $regex = $params->{sr};

    return near 'search?'.build_urlencoded_utf8([
      utf8 => "\x{2713}",
      q => "$search repo:Perl/$repo",
      type => 'Code',
    ]),
  }
  elsif ($action eq 'tag') {
    my $tag_sha = shift @path;
    return $tags{$tag_sha} ||= do {
        my $res = $ua->get("https://api.github.com/repos/Perl/$repo/git/tags/$tag_sha");
        if ($res->{success}) {
            my $data = decode_json($res->{content});
            my $tag = $data->{tag} or die;
            final $repo, 'releases', 'tag', $tag;
        }
        else {
            [$res->{status}, [], []];
        }
    };
  }
  elsif ($action eq 'commitdiff' and my $parent = $params->{hp}) {
    return final $repo, 'compare', $parent . '...' . branch($def_branch, @path);
  }
  elsif ($action eq 'blobdiff') {
    # TODO currently ignoring file since github doesn't have that
    my ($branch, $file) = branch_path(@_);
    return final $repo, 'compare', join '...', split /\.\./, $branch, 2;
  }
  elsif ($action eq 'blobdiff_plain') {
    # TODO currently ignoring file since github doesn't have that
    my ($branch, $file) = branch_path(@_);
    return final $repo, 'compare', join('...', split /\.\./, $branch, 2) . '.patch';
  }
  elsif ($new_action = $actions{$action}) {
    return final $repo, $new_action;
  }
  elsif ($new_action = $branch_actions{$action}) {
    return final $repo, $new_action, branch($def_branch, @path);
  }
  elsif ($new_action = $path_actions{$action}) {
    return final $repo, $new_action, branch_path($def_branch, @path);
  }
  elsif ($action eq 'commitdiff_plain') {
    return final $repo, 'commit', branch($def_branch, @path) . '.diff';
  }
  elsif ($action eq 'patch') {
    return final $repo, 'commit', branch($def_branch, @path) . '.patch';
  }
  elsif ($action eq 'snapshot') {
    return final $repo, 'archive', branch($def_branch, @path);
  }

  return near 'perl5';
};
