# Do /TRIGGER HELP for help
#
# Changelog 0.6.1+:
# - fixed spaces in trigger rules output
# - fixed saving settings with "/script unload trigger" by Valentin Batz (senneth)
# - added -invites

use strict;
use Irssi 20020324 qw (command_bind command_runsub command signal_add_first signal_continue signal_stop);
use Text::ParseWords;
use IO::File;
use Data::Dumper; 
use vars qw($VERSION %IRSSI);

$VERSION = '0.6.1+';
%IRSSI = (
	authors  	=> 'Wouter Coekaerts',
	contact  	=> 'wouter@coekaerts.be',
	name    	=> 'trigger',
	description 	=> 'executes an irssi command or replace text, triggered by a message,notice,join,part,quit,kick,topic or invite',
	license 	=> 'GPLv2',
	url     	=> 'http://wouter.coekaerts.be/irssi/',
	changed  	=> '29/01/04',
);

my @triggers;

sub cmd_help {
	Irssi::print ( <<SCRIPTHELP_EOF

TRIGGER DELETE <number>|<regexp>
TRIGGER LIST
TRIGGER SAVE 
TRIGGER RELOAD
TRIGGER ADD %|[-<types>] [-regexp <regexp>] [-modifiers <modifiers>] [-channels <channels>] [-masks <masks>] [-hasmode <hasmode>] [-hasflag <hasflag>]
            [-command <command>] [-replace <replace>] [-once]

When to match:
     -<types>: Trigger on these types of messages. The different types are:
                 publics,privmsgs,pubactions,privactions,pubnotices,privnotices,joins,parts,quits,kicks,topics,invites
                 -all is an alias for all of them.
     -regexp: the message must match <regexp>. (see man 7 regex)
     -modifiers: use <modifiers> for the regexp. The modifiers you may use are:
                     i: Ignore case.
                     g: Match as many times as possible.
     -channels: only trigger in <channels>. a space-delimited list. (use quotes)
                examples: '#chan1 #chan2' or 'IRCNet/#channel'
     -masks: only for messages from someone mathing one of the <masks> (space seperated)
     -hasmode: only if the person who triggers it has the <hasmode>
                examples: '-o' means not opped, '+ov' means opped OR voiced, '-o&-v' means not opped AND not voiced
     -hasflag: only works if friends.pl (friends_shasta.pl) or people.pl is loaded
               only trigger if the person who triggers it has <hasflag> in the script

What to do when it matches:
     -command: execute <command>
                You are able to use \$1, \$2 and so on generated by your regexp pattern.
                For multiple command \$; can be used as seperator
                The following variables are also expanded:          
                   \$T: Server tag
                   \$C: Channel name
                   \$N: Nickname of the person who triggered this command
                   \$A: His address (foo\@bar.com),
                   \$I: His ident (foo)
                   \$H: His hostname (bar.com)
                   \$M: The complete message

     -replace: replaces the matching part with <replace> in your irssi (requires a <regexp>)
     -once: remove the trigger if it is triggered, so it only executes once and then is forgotten.

Examples:
 knockout people who do a !list:
   /TRIGGER ADD -publics -channels "#channel1 #channel2" -modifiers i -regexp ^!list -command "KN \$N This is not a warez channel!"
 react to !echo commands from people who are +o in your friends-script:
   /TRIGGER ADD -publics -regexp '^!echo (.*)' -hasflag '+o' -command 'say \$1'
 ignore all non-ops on #channel
   /TRIGGER ADD -publics -channels "#channel" -hasmode '-o' -stop

Examples with -replace:
 replace every occurence of shit with sh*t, case insensitive
   /TRIGGER ADD -modifiers i -regexp shit -replace sh*t
 strip all colorcodes from *!lamer\@*
   /TRIGGER ADD -masks *!lamer\@* -regexp '\\x03\\d?\\d?(,\\d\\d?)?|\\x02|\\x1f|\\x16|\\x06' -replace ''
 never let *!bot1\@foo.bar or *!bot2\@foo.bar hilight you
 (this works by cutting your nick in 2 different parts, 'myn' and 'ick' here)
 you don't need to understand the -replace argument, just trust that it works if the 2 parts separately don't hilight.
   /TRIGGER ADD -masks '*!bot1\@foo.bar *!bot2\@foo.bar' -regexp '(myn)(ick)' -replace '\$1\\x02\\x02\$2'
 avoid being hilighted by !top10 in eggdrops with stats.mod (but show your nick in bold)
   /TRIGGER ADD -publics -regexp '(Top.0\\(.*\\): 1.*)(my)(nick)' -replace '\$1\\x02\$2\\x02\\x02\$3\\x02'
 Convert a Windows-1252 Euro to an ISO-8859-15 Euro (same effect as euro.pl)
   /TRIGGER ADD -regexp '\\x80' -replace '\\xA4'
 Show tabs as spaces, not the inverted I (same effect as tab_stop.pl)
   /TRIGGER ADD -regexp '\\t' -replace '    '

WARNING: Be very careful when you use the 'eval' or 'exec' command with parameters that come from a remote user. Only use them if you understand the risk.
SCRIPTHELP_EOF
   ,MSGLEVEL_CLIENTCRAP);
} # /

#switches in -all option
my @trigger_all_switches = ('publics','privmsgs','pubactions','privactions','pubnotices','privnotices','joins','parts','quits','kicks','topics','invites');
#list of all switches
my @trigger_switches = @trigger_all_switches;
push @trigger_switches, 'stop','once';
#parameters (with an argument)
my @trigger_params = ('masks','channels','modifiers','regexp','command','replace','hasmode','hasflag');
#list of all options (including switches)
my @trigger_options = ('all');
push @trigger_options, @trigger_switches;
push @trigger_options, @trigger_params;

#########################################
### catch the signals & do your thing ###
#########################################

# "message public", SERVER_REC, char *msg, char *nick, char *address, char *target
signal_add_first("message public" => sub {check_signal_message(\@_,1,4,2,3,'publics');});
# "message private", SERVER_REC, char *msg, char *nick, char *address
signal_add_first("message private" => sub {check_signal_message(\@_,1,-1,2,3,'privmsgs');});
# "message irc action", SERVER_REC, char *msg, char *nick, char *address, char *target
signal_add_first("message irc action" => sub {
	if ($_[4] eq $_[0]->{nick}) {
		check_signal_message(\@_,1,-1,2,3,'privactions');
	} else {
		check_signal_message(\@_,1,4,2,3,'pubactions');
	}
});
# "message irc notice", SERVER_REC, char *msg, char *nick, char *address, char *target
signal_add_first("message irc notice" => sub {
	if ($_[4] eq $_[0]->{nick}) {
		check_signal_message(\@_,1,-1,2,3,'privnotices');
	} else {
		check_signal_message(\@_,1,4,2,3,'pubnotices');
	}
});

# "message join", SERVER_REC, char *channel, char *nick, char *address
signal_add_first("message join" => sub {check_signal_message(\@_,-1,1,2,3,'joins');});
# "message part", SERVER_REC, char *channel, char *nick, char *address, char *reason
signal_add_first("message part" => sub {check_signal_message(\@_,4,1,2,3,'parts');});
# "message quit", SERVER_REC, char *nick, char *address, char *reason
signal_add_first("message quit" => sub {check_signal_message(\@_,3,-1,1,2,'quits');});
# "message kick", SERVER_REC, char *channel, char *nick, char *kicker, char *address, char *reason
signal_add_first("message kick" => sub {check_signal_message(\@_,5,1,3,4,'kicks');});
# "message topic", SERVER_REC, char *channel, char *topic, char *nick, char *address
signal_add_first("message topic" => sub {check_signal_message(\@_,2,1,3,4,'topics');});
# "message invite", SERVER_REC, char *channel, char *nick, char *address
signal_add_first("message invite" => sub {check_signal_message(\@_,-1,1,2,3,'invites');});

# check the triggers on $signal's $parammessage parameter, for triggers with $condition set
# in $paramchannel, for $paramnick!$paramaddress
#  set $param* to -1 if not present (only allowed for message and channel)
sub check_signal_message {
	my ($signal,$parammessage,$paramchannel,$paramnick,$paramaddress,$condition) = @_;
	my ($trigger, $channel, $matched, $changed, $context);
	my $server = $signal->[0];
	my $message = ($parammessage == -1) ? '' : $signal->[$parammessage];

TRIGGER:
	for (my $index=0;$index < scalar(@triggers);$index++) { 
		my $trigger = $triggers[$index];
		if (!$trigger->{"$condition"}) {
			next; # wrong type of message
		}
		if ($trigger->{'channels'}) { # check if the channel matches
			if ($paramchannel == -1) {
				next;
			}
			my $matches = 0;
			foreach $channel (split(/ /,$trigger->{'channels'})) {
				if (lc($signal->[$paramchannel]) eq lc($channel)
				  || lc($server->{'tag'}.'/'.$signal->[$paramchannel]) eq lc($channel)
				  || lc($server->{'tag'}.'/') eq lc($channel)) {
					$matches = 1;
					last; # this channel matches, stop checking channels
				}
			}
			if (!$matches) {
				next; # this trigger doesn't match, try next trigger...
			}
		}
		# check the mask
		if ($trigger->{'masks'} && !$server->masks_match($trigger->{'masks'}, $signal->[$paramnick], $signal->[$paramaddress])) {
			next; # this trigger doesn't match

		}
		# check hasmodes
		if ($trigger->{'hasmode'}) {
			my ($channel, $nick);
			( $paramchannel != -1
			  and $channel = $server->channel_find($signal->[$paramchannel])
			  and $nick = $channel->nick_find($signal->[$paramnick])
			) or next;

			my $modes = ($nick->{'op'}?'o':'').($nick->{'voice'}?'v':'').($nick->{'halfop'}?'h':'');
			if (!check_modes($modes,$trigger->{'hasmode'})) {
				next;
			}	
		}

		# check hasflags
		if ($trigger->{'hasflag'}) {
			my $channel = ($paramchannel == -1) ? undef : $signal->[$paramchannel];
			my $flags = get_flags ($server->{'chatnet'},$channel,$signal->[$paramnick],$signal->[$paramaddress]);
			if (!defined($flags)) {
				next;
			}
			if (!check_modes($flags,$trigger->{'hasflag'})) {
				next;
			}
		}	
		
		# the only check left, is the regexp matching...
		if (defined($trigger->{'replace'}) && $parammessage != -1) { # it's a -replace
			# if you know a better way to do this, let me know:
			eval('$matched = ($signal->[$parammessage] =~ s�'. $trigger->{'regexp'} . '�' . $trigger->{'replace'} . '�' . $trigger->{'modifiers'} . ');');
			$changed = $changed || $matched;
		}
		if ($trigger->{'command'}) {
			my @vars;
			# check if the message matches the regexp (with the modifiers embedded), and put ($1,$2,$3,...) in @vars
			@vars = $message =~ m/(?$trigger->{'modifiers'})$trigger->{'regexp'}/;
			if (@vars){ # if it matched
				$matched = 1;
				my $command = $trigger->{'command'};
				my $expands = {
					'M' => $message,
					'T' => $server->{'tag'},
					'C' => (($paramchannel == -1) ? '' : $signal->[$paramchannel]),
					'N' => (($paramnick == -1) ? '' : $signal->[$paramnick]),
					'A' => (($paramaddress == -1) ? '' : $signal->[$paramaddress]),
					'I' => (($paramaddress == -1) ? '' : split(/\@/,$signal->[$paramaddress]),2)[0],
					'H' => (($paramaddress == -1) ? '' : split(/\@/,$signal->[$paramaddress]),2)[1],
					'$' => '$',
					';' => "\x00"
				};
				# $1 = the stuff behind the $ we want to expand: a number, or a character from %expands
				$command =~ s/\$(\d+|[^0-9])/expand(\@vars,$1,$expands)/ge;
				
				
				if ($paramchannel!=-1 && $server->channel_find($signal->[$paramchannel])) {
					$context = $server->channel_find($signal->[$paramchannel]);
				} else {
					$context = $server;
				}
				
				foreach my $commandpart (split /\x00/,$command) {
					$commandpart =~ s/^ +//;  # remove spaces in front
					$context->command($commandpart);
				}
			}
		} elsif ($message =~ m/(?$trigger->{'modifiers'})$trigger->{'regexp'}/) {
			$matched = 1;
		}
		if ($matched) {
			if ($trigger->{'stop'}) {
				signal_stop;
			}
			if ($trigger->{'once'}) {
				splice (@triggers,$index,1);
				$index--; # index of next trigger now is the same as this one was
			}
		}
	}
	if ($changed) { # changed with -replace
		signal_continue(@$signal);
	}
}

# used in check_signal_message, to expand $'s
sub expand {
	my ($vars,$to_expand,$expands) = @_;
	if ($to_expand =~ /^\d+$/) { # a number => look up in $vars
		return ($to_expand > @{$vars}) ? '' : $vars->[$to_expand-1];
	} else { # look up in $expands
		return $expands->{$to_expand};
	}
}

sub check_modes {
	my ($has_modes, $need_modes) = @_;
	my $matches;
	my $switch = 1; # if a '-' if found, will be 0 (meaning the modes should not be set)
	foreach my $need_mode (split /&/,$need_modes) {
		$matches = 0;
		foreach my $char (split //,$need_mode) {
			if ($char eq '-') {
				$switch = 0;
			} elsif ($char eq '+') {
				$switch = 1;
			} elsif ((index($has_modes,$char) != -1) == $switch) {
				$matches = 1;
				last;
			}
		}
		if (!$matches) {
			return 0;
		}
	}
	return 1;
}

# get someones flags from people.pl or friends(_shasta).pl
sub get_flags {
	my ($chatnet, $channel, $nick, $address) = @_;
	my $flags;
	no strict 'refs';
	if (defined %{ 'Irssi::Script::people::' }) {
		if (defined ($channel)) {
			$flags = (&{ 'Irssi::Script::people::find_local_flags' }($chatnet,$channel,$nick,$address));
		} else {
			$flags = (&{ 'Irssi::Script::people::find_global_flags' }($chatnet,$nick,$address));
		}
		$flags = join('',keys(%{$flags}));
	} else {
		my $shasta;
		if (defined %{ 'Irssi::Script::friends_shasta::' }) {
			$shasta = 'friends_shasta';
		} elsif (defined &{ 'Irssi::Script::friends::get_idx' }) {
			$shasta = 'friends';
		}
		if (!$shasta) {
			return undef;
		}
		my $idx = (&{ 'Irssi::Script::'.$shasta.'::get_idx' }($nick,$address));
		if ($idx == -1) {
			return '';
		}
		$flags = (&{ 'Irssi::Script::'.$shasta.'::get_friends_flags' }($idx,undef));
		if ($channel) {
			$flags .= (&{ 'Irssi::Script::'.$shasta.'::get_friends_flags' }($idx,$channel));
		}
	}
	return $flags;
}

################################
### manage the triggers-list ###
################################

# TRIGGER SAVE
sub cmd_save {
	my $filename = Irssi::settings_get_str('trigger_file');
	my $io = new IO::File $filename, "w";
	if (defined $io) {
		my $dumper = Data::Dumper->new([\@triggers]);
		$dumper->Purity(1)->Deepcopy(1);
		$io->print($dumper->Dump);
		$io->close;
	}
	Irssi::print("Triggers saved to ".$filename);
}

# save on unload
sub sig_command_script_unload {
	my $script = shift;
	if ($script =~ /(.*\/)?$IRSSI{'name'}(\.pl)?$/) {
		cmd_save();
	}
}

# TRIGGER LOAD
sub cmd_load {
	my $converted = 0;
	my $filename = Irssi::settings_get_str('trigger_file');
	my $io = new IO::File $filename, "r";
	if (not defined $io) {
		if (-e $filename) {
			Irssi::print "error opening triggers file";
		}
		return;
	}
	if (defined $io) {
		no strict 'vars';
		my $text;
		$text .= $_ foreach ($io->getlines);
		my $rep = eval "$text";
		@triggers = @$rep if ref $rep;
		
		# convert old names: notices => pubnotices, actions => pubactions
		foreach $trigger (@triggers) {
			foreach $oldname ('notices','actions') {
				if ($trigger->{$oldname}) {
					delete $trigger->{$oldname};
					$trigger->{'pub'.$oldname} = 1;
					$converted = 1;
				}
			}
		}
	}
	Irssi::print("Triggers loaded from ".$filename);
	if ($converted) {
		Irssi::print("Trigger: Converted old (confusing) params -notices and -actions to -pubnotices and pubactions.\nTriggers file will be in new format next time it's saved.");
	}
}

# converts a trigger back to "-switch -options 'foo'" form
sub to_string {
	my ($trigger) = @_;
	my $string;
	
	# check if all @trigger_all_switches are set
	my $all_set = 1;
	foreach my $switch (@trigger_all_switches) {
		if (!$trigger->{$switch}) {
			$all_set = 0;
			last;
		}
	}
	if ($all_set) {
		$string .= '-all ';	
	} else {
		foreach my $switch (@trigger_switches) {
			if ($trigger->{$switch}) {
				$string .= '-'.$switch.' ';
			}
		}
	}

	foreach my $param (@trigger_params) {
		if ($trigger->{$param} || ($param eq 'replace' && defined($trigger->{'replace'}))) {
			$string .= '-' . $param . " '$trigger->{$param}'".' ';
		}
	}
	return $string;
}

# find a trigger (for REPLACE and DELETE), returns index of trigger, or -1 if not found
sub find_trigger {
	my ($data) = @_;
	#my $index = $data-1;
	if ($data =~ /^[0-9]*$/ and defined($triggers[$data-1])) {
		return $data-1;
	}
	for (my $i=0;$i<scalar(@triggers);$i++) {
		if ($triggers[$i]->{'regexp'} eq $data) {
			return $i;
		}
	}
	return -1; # not found
}


# TRIGGER ADD
sub cmd_add {
	my ($data, $server, $item) = @_;
	my @args = &shellwords($data);
	
	my $trigger = parse_options({},@args);
	if ($trigger) {
		push @triggers, $trigger;
		Irssi::print("Added trigger " . scalar(@triggers) .": ". to_string($trigger));
	}
}

# TRIGGER REPLACE <NR>|<regexp>
sub cmd_replace {
	my ($data, $server, $item) = @_;
	my @args = &shellwords($data);
	my $index = find_trigger(shift @args);
	if ($index == -1) {
		Irssi::print "Trigger not found.";
	} else {
		parse_options($triggers[$index],@args);
		Irssi::print("Trigger " . ($index+1) ." changed to: ". to_string($triggers[$index]));
	}	
}

# parses options to TRIGGER ADD and TRIGGER REPLACE
sub parse_options {
	my ($trigger,@args) = @_;
ARGS:	for (my $arg = shift @args; $arg; $arg = shift @args) {
		# -<param>
		foreach my $param (@trigger_params) {
			if ($arg eq '-'.$param) {
				$trigger->{$param} = shift @args;
				next ARGS;
			}
		}
		# -all
		if ($arg eq '-all') {
			foreach my $switch (@trigger_all_switches) {
				$trigger->{$switch} = 1;
			}
			next ARGS;
		}

		# -[no]<switch>
		foreach my $switch (@trigger_switches) {
			# -<switch>
			if ($arg eq '-'.$switch) {
				$trigger->{$switch} = 1;
				next ARGS;
			}
			# -no<switch>
			elsif ($arg eq '-no'.$switch) {
				$trigger->{$switch} = undef;
				next ARGS;
			}
		}
		Irssi::print("Unknown option: $arg");
		return undef;
	}

	# check if it has at least one type
	my $has_a_type;
	foreach my $type (@trigger_all_switches) {
		if ($trigger->{$type}) {
			$has_a_type = 1;
			last;
		}
	}
	if (!$has_a_type) {
		Irssi::print("Warning: this trigger doesn't trigger on any type of message. you probably want to add -publics or -all");
	}

	return $trigger;
}

# TRIGGER DELETE <num>|<regexp>
sub cmd_del {
	my ($data, $server, $item) = @_;
	my @args = &shellwords($data);
	my $index = find_trigger($data);
	if ($index == -1) {
		Irssi::print ("Trigger $data not found.");
		return;
	}
	print("Deleted ". ($index+1) .": ". to_string($triggers[$index]));
	splice (@triggers,$index,1);
}

# TRIGGER LIST
sub cmd_list {
	#my (@args) = @_;
	Irssi::print ("Trigger list:",MSGLEVEL_CLIENTCRAP);
	my $i=1;
	foreach my $trigger (@triggers) {
		Irssi::print(" ". $i++ .": ". to_string($trigger),MSGLEVEL_CLIENTCRAP);
	}
}

######################
### initialisation ###
######################

command_bind('trigger help',\&cmd_help);
command_bind('help trigger',\&cmd_help);
command_bind('trigger add',\&cmd_add);
command_bind('trigger replace',\&cmd_replace);
command_bind('trigger list',\&cmd_list);
command_bind('trigger delete',\&cmd_del);
command_bind('trigger save',\&cmd_save);
command_bind('trigger reload',\&cmd_load);
command_bind 'trigger' => sub {
    my ( $data, $server, $item ) = @_;
    $data =~ s/\s+$//g;
    command_runsub ( 'trigger', $data, $server, $item ) ;
};
signal_add_first 'default command trigger' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::signal_add_first('command script load', 'sig_command_script_unload');
Irssi::signal_add_first('command script unload', 'sig_command_script_unload');
Irssi::signal_add('setup saved', 'cmd_save');

# This makes tab completion work
Irssi::command_set_options('trigger add',join(' ',@trigger_options));

Irssi::settings_add_str($IRSSI{'name'}, 'trigger_file', Irssi::get_irssi_dir()."/triggers");

cmd_load();
