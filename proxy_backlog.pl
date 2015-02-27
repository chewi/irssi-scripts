# this script is still experimental, don't expect it to work as expected :)
# see http://wouter.coekaerts.be/site/irssi/proxy_backlog
use Irssi;
use Irssi::TextUI;
use File::Basename;
use IPC::Run3;

$VERSION = "0.0.1";
%IRSSI = (
	authors         => "Wouter Coekaets",
	contact         => "coekie@irssi.org",
	name            => "proxy_backlog",
	url             => "http://wouter.coekaerts.be/site/irssi/proxy_backlog",
	description     => "sends backlog from irssi to clients connecting to irssiproxy",
	license         => "GPL",
	changed         => "2015-02-26"
);

sub sendbacklog {
	my ($server) = @_;
	my @log2ansi = ["perl", dirname(__FILE__) . "/log2ansi.pl"];
	Irssi::print("Sending backlog to proxy client for " . $server->{'tag'});
	Irssi::signal_add_first('print text', 'stop_sig');
	Irssi::signal_emit('server incoming', $server,':proxy NOTICE * :Sending backlog');
	foreach my $channel ($server->channels) {
		my $buffer = "";
		my $window = $server->window_find_item($channel->{'name'});
		for (my $line = $window->view->get_lines; defined($line); $line = $line->next) {
			$buffer .= $line->get_text(0) . "\n";
		}
		run3(@log2ansi, \$buffer, \$buffer, \undef);
		my @lines = split /\n/, $buffer;
		foreach my $line (@lines) {
			Irssi::signal_emit('server incoming', $server,':proxy NOTICE ' . $channel->{'name'} .' :' . $line);
		}
	}
	Irssi::signal_emit('server incoming', $server,':proxy NOTICE * :End of backlog');
	Irssi::signal_remove('print text', 'stop_sig');
}

sub stop_sig {
	Irssi::signal_stop();
}

Irssi::signal_add('message irc own_ctcp', sub {
	my ($server, $cmd, $data, $target) = @_;
	print ("cmd:$cmd data:$data target:$target");
	if ($cmd eq 'IRSSIPROXY' && $data eq 'BACKLOG SEND' && $target eq '-proxy-') {
		sendbacklog($server);
	}
});
