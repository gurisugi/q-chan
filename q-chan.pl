#! /usr/bin/env perl
use strict;
use warnings;
use 5.10.0;
use FindBin;

use AnySan;
use AnySan::Provider::IRC;
use Config::PL;
use Redis;
use List::MoreUtils qw/any/;

my $conf;
if ( -e 'config_local.pl' ) {
    $conf = config_do 'config_local.pl';
}
else {
    $conf = config_do 'config.pl';
}

my $bot_nickname = 'qchan';
my $irc          = irc
    $conf->{host},
    port          => $conf->{port},
    nickname      => $bot_nickname,
    password      => $conf->{password},
    channels      => $conf->{channels},
    interval      => 0,
    on_disconnect => sub {
        warn 'disconnected!';
        sleep 10;
        shift->connect;
    },
    enable_ssl => $conf->{enable_ssl},
;

my $redis = Redis->new(
    encoding  => undef,
    reconnect => 1,
    every     => 200,
);


AnySan->register_listener(
    oppai => {
        cb => sub {
            my $r = shift;
            my $from_nick = $r->from_nickname;
            my $message = ( $r->message );
            return unless $message =~ /^$bot_nickname/;

            my $m = _parse_message( $message, $bot_nickname );
            return unless $m;

            my $reply;
            my ( $method, @args ) = split ' ', $m;

            if ( _is_valid_method( $method ) ) {
                $reply = eval 'cmd_'.$method.'( $redis, @args )';
                $r->send_reply( $reply );
                return;
            }
            else {
                $r->send_reply( '＿ﾉ乙(､ﾝ､)つ'."'".$method."'".'？' );
                return;
            }
        }
    }
);

AnySan->run;



sub _parse_message {
    my ( $message, $bot_nickname ) = @_;
    $message =~ /(^$bot_nickname:?)([^:]+)/;
    my $q_chan = $1
        or return undef;
    my $he_says = $2
        or return undef;
    $he_says =~ s/^\s//;

    return $he_says ? $he_says : undef;
}

sub _is_valid_method {
    my ( $method ) = @_;
    my @methods = (
        'show',
        'add',
        'done',
        'all',
        'help',
    );

    return ( any { $method =~ /^$_$/ } @methods ) ? 1 : 0;
}



##### cmds ####

sub cmd_all {
    my $redis = shift;
    my @keys = $redis->keys('*');
    my $reply = scalar @keys
        ? join ', ', map { $_.' => [ '.join( ', ', $redis->lrange($_, 0, -1) ).' ]' } @keys
        : 'Nobody in any queue.';
    return $reply;
}

sub cmd_help {
    my $reply =  "＿ﾉ乙(､ﾝ､)つ https://github.com/gurisugi/q-chan/blob/master/README.md";
    return $reply;
}

sub cmd_show {
    my $redis = shift;
    my ( $key_user ) = @_;

    my @queue_mem = $redis->lrange( $key_user, 0, -1 );
    my $reply = scalar @queue_mem
        ? $key_user.' => [ '.join( ', ', @queue_mem ).' ]'
        : 'Nobody in '.$key_user.' queue.';
    return $reply;
}

sub cmd_done {
    my $redis = shift;
    my ( $key_user, $target_user ) = @_;

    my $res = $redis->lpop( $key_user );
    my $reply = $res ? 'done success' : 'done failed';
    return $reply;
}

sub cmd_add {
    my $redis = shift;
    my ( $key_user, $target_user ) = @_;

    my $res = $redis->rpush( $key_user, $target_user );
    my $reply = $res ? 'add success.' : 'add failed.';
    return $reply;
}
