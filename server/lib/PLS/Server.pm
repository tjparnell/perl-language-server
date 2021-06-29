package PLS::Server;

use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Signal;
use IO::Async::Stream;
use IO::Handle;
use JSON::PP;
use Scalar::Util qw(blessed);

use PLS::Server::Request::Factory;
use PLS::Server::Response;

=head1 NAME

PLS::Server

=head1 DESCRIPTION

Perl Language Server

This server communicates to a language client through STDIN/STDOUT.

=head1 SYNOPSIS

    my $server = PLS::Server->new();
    $server->run() # never returns

=cut

sub new
{
    my ($class) = @_;

    return
      bless {
             loop             => IO::Async::Loop->new(),
             stream           => undef,
             running_futures  => {},
             pending_requests => {}
            }, $class;
} ## end sub new

sub run
{
    my ($self) = @_;

    STDOUT->blocking(0);

    $self->{stream} = IO::Async::Stream->new_for_stdio(
        autoflush => 1,
        on_read   => sub {
            my ($stream, $buffref, $eof) = @_;

            return 0 if ($$buffref !~ /\r\n\r\n/);

            my ($headers) = $$buffref =~ /^(.*)\r\n\r\n/sm;
            $$buffref =~ s/^.*\r\n\r\n//;
            my %headers = map { split /: /, $_ } split /\r\n/, $headers;

            return 0 if (length($$buffref) < $headers{'Content-Length'});

            my $json    = substr $$buffref, 0, $headers{'Content-Length'}, '';
            my $content = JSON::PP->new->utf8->decode($json);

            $self->handle_client_message($content);

            return 1;
        }
    );

    $self->{loop}->add($self->{stream});
    $self->{loop}->add(IO::Async::Signal->new(name => 'INT',  on_receipt => sub { $self->{loop}->stop() }));
    $self->{loop}->add(IO::Async::Signal->new(name => 'TERM', on_receipt => sub { $self->{loop}->stop() }));

    $self->{loop}->loop_forever();

    return;
} ## end sub run

sub handle_client_message
{
    my ($self, $message) = @_;

    if (length $message->{method})
    {
        my $request = PLS::Server::Request::Factory->new($message);

        if (blessed($request) and $request->isa('PLS::Server::Response'))
        {
            $self->send_message($request);
            return;
        }

        return if (not blessed($request) or not $request->isa('PLS::Server::Request'));
        my $response = $request->service($self);
        $self->send_message($response);
    } ## end if (length $message->{...})
    else
    {
        my $response = PLS::Server::Response->new($message);
        my $request  = $self->{pending_requests}{$response->{id}};
        return if (not blessed($request) or not $request->isa('PLS::Server::Request'));
        $self->{loop}->later(sub { $request->handle_response($response, $self) });
    } ## end else [ if (length $message->{...})]

    return;
} ## end sub handle_client_message

sub send_message
{
    my ($self, $message) = @_;

    return if (not blessed($message) or not $message->isa('PLS::Server::Message'));
    my $json   = $message->serialize();
    my $length = length $json;
    return $self->{stream}->write("Content-Length: $length\r\n\r\n$json");
} ## end sub send_message

sub send_server_request
{
    my ($self, $request) = @_;

    if ($request->{notification})
    {
        delete $request->{notification};
    }
    else
    {
        $request->{id} = ++$self->{last_request_id};
        $self->{pending_requests}{$request->{id}} = $request;
    }

    return $self->send_message($request);
} ## end sub send_server_request

1;
