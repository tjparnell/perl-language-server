package PLS::Server::Response::Location;
use parent q(PLS::Server::Response);

use strict;
use warnings;

use PLS::Parser::Document;
use PLS::Parser::Index;
use PLS::Server::State;

sub new
{
    my ($class, $request) = @_;

    my $self = {
                id     => $request->{id},
                result => undef
               };

    bless $self, $class;

    my $document = PLS::Parser::Document->new(uri => $request->{params}{textDocument}{uri});

    return $self unless (ref $document eq 'PLS::Parser::Document');

    my $results = $document->go_to_definition(@{$request->{params}{position}}{qw(line character)});

    if (ref $results eq 'ARRAY')
    {
        foreach my $result (@$results)
        {
            delete $result->{signature};
        }
    } ## end if (ref $results eq 'ARRAY'...)

    $self->{result} = $results;
    return $self;
} ## end sub new

1;
