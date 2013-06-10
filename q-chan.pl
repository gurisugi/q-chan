use strict;
use warnings;
use 5.10.0;
use FindBin;

use AnySan;
use AnySan::Provider::IRC;
use Config::PL;
use Redis;

my $conf         = config_do 'config.pl';
my $bot_nickname = 'q-chan';
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
    enable_ssl => 1,
;

my $redis = Redis->new(
    encoding  => undef,
    reconnect => 1,
    every     => 200,
);

$redis->flushall;

AnySan->register_listener(
    oppai => {
        cb => sub {
            my $r = shift;
            my $from_nick = $r->from_nickname;
            my $message = ( $r->message );
            return unless $message =~ /^q_chan:/;

            my $reply;
            my $m = _parse_message( $message );
            unless ( $m ) {
                $r->send_reply( "(*'-') やあ." );
                return;
            }

            my ($q_nick, $method, $target_nick) = split ' ', $m;
            $q_nick ||= '';
            $method ||= '';
            $target_nick ||= '';

            if ($method =~ /^show$/) {
                my @res = $redis->lrange( $q_nick, 0, -1 );
                my $q = join ', ', @res;
                $reply = $q ? "$from_nick: $q_nick => [ $q ]" : "No one in $q_nick queue."
            }
            elsif ( $method =~ /^add$/ ) {
                unless ( $target_nick ) {
                    $redis->rpush( $q_nick, $from_nick );
                    $reply = "$from_nick: ok. $from_nick add to $q_nick queue.";
                }
                else {
                    $redis->rpush( $q_nick, $target_nick );
                    $reply = "$from_nick: ok. $target_nick add to $q_nick queue.";
                }
            }
            elsif ( $method =~ /^done$/ ) {
                unless ( $target_nick ) {
                    my @lis = $redis->lrange( $q_nick, 0, 0 );
                    $target_nick = $lis[0];
                    unless ( $target_nick ) {
                        $r->send_reply( "No one in $q_nick queue." );
                        return;
                    }
                }
                if ( $redis->lrem( $q_nick, 1, $target_nick ) ) {
                    my @next_nick = $redis->lrange( $q_nick, 0, 0 );
                    my $next_message = $next_nick[0] ? "And next one is $next_nick[0]." : "No one in $q_nick queue.";
                    $reply = "$from_nick: OK. Delete $target_nick from $q_nick queue. $next_message";
                }
                else {
                    $reply = "$from_nick: $target_nick not found in $q_nick queue.";
                }
            }
            elsif ( $q_nick =~ /^all$/ ) {
                my @keys = $redis->keys( '*' );
                for my $key ( @keys ) {
                    my @lis = $redis->lrange( $key, 0, -1 );
                    my $value = join ', ', @lis;
                    $reply = "$key => [ $value ]";
                    $r->send_reply( $reply );
                }
                return;
            }
            elsif ( $q_nick =~ /^help$/ ) {
                $r->send_reply( "(*'-')つ https://github.com/gurisugi/q-chan" );
                return;
            }
            else {
                $reply = "$m |'-')?";
            }

            return unless $reply;

            $r->send_reply( $reply );
        }
    }
);

AnySan->run;


sub _parse_message {
    my $message = shift;
    $message =~ /(^q_chan:)(.+)/;
    my $q_chan = $1
        or return undef;
    my $he_says = $2
        or return undef;
    $he_says =~ s/^\s//;

    return $he_says ? $he_says : undef;
}
