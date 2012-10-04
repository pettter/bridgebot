#!/usr/bin/perl
# BridgeBot - a simple Perl bot for bridging the gap between an IRC
# channel and an XMPP MUC groupchat.
# 
# <standard legalese disclaimers>
# 
# Not that special, not very useful, but there seemed to be no bots having
# this specific functionality advertised, and that's what I needed.
# 
# (K) Petter Ericson - petter.ericson@codemill.se

use utf8;
use AnyEvent;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::XMPP::Util qw/split_jid/;
use AnyEvent::XMPP::Ext::Disco;
use AnyEvent::XMPP::Ext::MUC;
use AnyEvent::XMPP::Ext::MUC::Message;
use AnyEvent::IRC::Client;
use Data::Dumper;
use warnings;
use strict;


#Some configuration
my $xmppconf = {
	nick => '',
	jid => '',
	password => '',
	room => ''

};

my $ircconf = {
	nick => '',
	server => '',
	port   => 6667,
	channel => ''
};

# The event loop conditional
my $j = AnyEvent->condvar;


#IRC connection object
my $irc = new AnyEvent::IRC::Client;

#XMPP objects (xmpp, disco and muc)
my  $xmpp = AnyEvent::XMPP::IM::Connection->new (
	jid              => $xmppconf->{'jid'},
	password         => $xmppconf->{'password'},
);

$xmpp->add_extension( my $disco = AnyEvent::XMPP::Ext::Disco->new );
$xmpp->add_extension( my $muc = AnyEvent::XMPP::Ext::MUC->new (disco => $disco));


#IRC callbacks, simple, stupid
$irc->reg_cb (
# Once registered, join the channel
	registered => sub {
		print "Joining IRC channel " . $ircconf->{ 'channel' } . "\n";
		$irc->send_srv(JOIN => $ircconf->{ 'channel' });
	},
#On receit of a public message
	publicmsg => sub {
		my ($con, $channel, $ircmsg) = @_;
		# extract nick
		my $nick = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});
		# and message
		my $message = $ircmsg->{params}->[1];
		# if we didn't send it
		if(not $nick eq $ircconf->{'nick'}) {
			# pass it on
			my $msg = AnyEvent::XMPP::Ext::MUC::Message->new(
				to => $xmppconf->{'room'},
				connection => $xmpp,
				body => $nick . ": ". $message,
				type => 'groupchat');
			$msg->send($muc->get_room($xmpp, $xmppconf->{'room'}));
		}
	}
);

#MUC callbacks, simple, stupid
$muc->reg_cb (
#On receit of a MUC message
	message => sub {
		my ($muc, $room, $msg, $is_echo) = @_;
		# if we didn't send it
		if(not $msg->from_nick eq $xmppconf->{'nick'}) {
			# pass it on
			$irc->send_srv(PRIVMSG => $ircconf->{'channel'},
				$msg->from_nick. ": " . $msg->any_body) ;
		}
	},
# Diagnostics
	join => sub {
		print "joined\n";
	}
);

$xmpp->reg_cb (
# Join chat when ready
	session_ready => sub {
		my ($con, $acc) = @_;
		print "XMPP session ready, joining chat\n";
		$muc->join_room($con, $xmppconf->{'room'}, $xmppconf->{'nick'})
	},
# Report errors
	error => sub {
		my ($con, $err) = @_;
		print "ERROR: " . $err->string . "\n";
	},
	message_error => sub {
		print "error";
	}
);
$xmpp->connect();
$irc->connect($ircconf->{'server'}, $ircconf->{'port'}, { nick => $ircconf->{'nick'} });
$j->wait;
$irc->disconnect();
