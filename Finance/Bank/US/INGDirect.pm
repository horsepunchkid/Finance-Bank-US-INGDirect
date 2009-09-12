package Finance::Bank::US::INGDirect;

use strict;

use Carp 'croak';
use LWP::UserAgent;
use HTTP::Cookies;
use Date::Parse;
use Data::Dumper;

our $VERSION = 0.0.2;

=pod

=head1 NAME

Finance::Bank::US::INGDirect - Check balances and transactions for US INGDirect accounts

=head1 SYNOPSIS

  use Finance::Bank::US::INGDirect;
  use Finance::OFX::Parse::Simple;

  my $ing = Finance::Bank::US::INGDirect->new(
      saver_id => '...',
      customer => '########',
      questions => {
          # Your questions may differ; examine the form to find them
          'AnswerQ1.4' => '...', # In what year was your mother born?
          'AnswerQ1.5' => '...', # In what year was your father born?
          'AnswerQ1.8' => '...', # What is the name of your hometown newspaper?
      },
      pin => '########',
  );

  my $parser = Finance::OFX::Parse::Simple->new;
  my @txs = @{$parser->parse_scalar($ing->recent_transactions)};
  my %accounts = $ing->accounts;

  for (@txs) {
      print "Account: $_->{account_id}\n";
      printf "%s %-50s %8.2f\n", $_->{date}, $_->{name}, $_->{amount} for @{$_->{transactions}};
      print "\n";
  }

=head1 DESCRIPTION

This module provides methods to access data from US INGdirect accounts,
including account balances and recent transactions in OFX format (see
Finance::OFX and related modules).

=cut

my $base = 'https://secure.ingdirect.com/myaccount';

=pod

=head1 METHODS

=head2 new( saver_id => '...', customer => '...', questions => [...], pin => '...' )

Return an object that can be used to retrieve account balances and statements.
See USAGE for examples of challenge questions.

=cut

sub new {
    my ($class, %opts) = @_;
    my $self = bless \%opts, $class;

    $self->{ua} ||= LWP::UserAgent->new(cookie_jar => HTTP::Cookies->new);

    _login($self);
    $self;
}

sub _login {
    my ($self) = @_;

    my $response = $self->{ua}->get("$base/INGDirect/login.vm");

    $response = $self->{ua}->post("$base/INGDirect/login.vm", [
        publicUserId => $self->{saver_id},
    ]);
    $response->is_redirect or croak "Initial login failed.";

    $response = $self->{ua}->get("$base/INGDirect/security_questions.vm");
    $response->is_success or croak "Retrieving challenge questions failed.";

    my @questions = map { s/^.*(AnswerQ.*)span".*$/$1/; $_ } grep /AnswerQ/, split('\n', $response->content);
    croak "Didn't understand questions." if @questions != 2;

    $response = $self->{ua}->post("$base/INGDirect/security_questions.vm", [
        TLSearchNum => $self->{customer},
        'customerAuthenticationResponse.questionAnswer[0].answerText' => $self->{questions}{$questions[0]},
        'customerAuthenticationResponse.questionAnswer[1].answerText' => $self->{questions}{$questions[1]},
        '_customerAuthenticationResponse.device[0].bind' => 'false',
    ]);
    $response->is_redirect or croak "Submitting challenge responses failed.";

    $response = $self->{ua}->get("$base/INGDirect/login_pinpad.vm");
    $response->is_success or croak "Loading PIN form failed.";

    my @keypad = map { s/^.*mouseUpKb\('([A-Z])'.*$/$1/; $_ }
        grep /onMouseUp="return mouseUpKb/,
        split('\n', $response->content);

    @keypad = map { shift @keypad; shift @keypad || () } @keypad;
    unshift(@keypad, pop @keypad);

    $response = $self->{ua}->post("$base/INGDirect/login_pinpad.vm", [
        'customerAuthenticationResponse.PIN' => join '', map { $keypad[$_] } split//, $self->{pin},
    ]);
    $response->is_redirect or croak "Submitting PIN failed.";

    $response = $self->{ua}->get("$base/INGDirect.html?command=viewAccountPostLogin");
    $response->is_success or croak "Final login failed.";
    $self->{_account_screen} = $response->content;
}

=pod

=head2 accounts( )

Retrieve a list of accounts:

  ( '####' => [ number => '####', type => 'Orange Savings', nickname => '...',
                available => ###.##, balance => ###.## ],
    ...
  )

=cut

sub accounts {
    my ($self) = @_;

    use HTML::Strip;
    my $hs = HTML::Strip->new;
    my @lines = grep /command=goToAccount/, split(/[\n\r]/, $self->{_account_screen});
    @lines = map { tr/\xa0/ /; $_ } split(/\n/, $hs->parse(join "\n", @lines));

    my %accounts;
    for (@lines) {
        my @data = splice(@lines, 0, 3);
        my %account;
        ($account{type} = $data[0]) =~ s/^\s*(.*?)\s*$/$1/;
        ($account{nickname}, $account{number}, $account{balance}) = split /\s/, $data[1];
        ($account{available} = $data[2]) =~ s/^\s*(.*?)\s*$/$1/;
        $accounts{$account{number}} = \%account;
    }

    %accounts;
}

=pod

=head2 recent_transactions( $account, $days )

Retrieve a list of transactions in OFX format for the given account
(default: all accounts) for the past number of days (default: 30).

=cut

sub recent_transactions {
    my ($self, $account, $days) = @_;

    $account ||= 'ALL';
    $days ||= 30;

    my $response = $self->{ua}->post("$base/download.qfx", [
        type => 'OFX',
        TIMEFRAME => 'STANDARD',
        account => $account,
        FREQ => $days,
    ]);
    $response->is_success or croak "OFX download failed.";

    $response->content;
}

=pod

=head2 transactions( $account, $from, $to )

Retrieve a list of transactions in OFX format for the given account
(default: all accounts) in the given time frame (default: pretty far in the
past to pretty far in the future).

=cut

sub transactions {
    my ($self, $account, $from, $to) = @_;

    $account ||= 'ALL';
    $from ||= '2000-01-01';
    $to ||= '2038-01-01';

    my @from = strptime($from);
    my @to = strptime($to);

    $from[4]++;
    $to[4]++;
    $from[5] += 1900;
    $to[5] += 1900;

    my $response = $self->{ua}->post("$base/download.qfx", [
        type => 'OFX',
        TIMEFRAME => 'VARIABLE',
        account => $account,
        startDate => "$from[4]/$from[3]/$from[5]",
        endDate   => "$to[4]/$to[3]/$to[5]",
    ]);
    $response->is_success or croak "OFX download failed.";

    $response->content;
}

1;

=pod

=head1 AUTHOR

This version by Steven N. Severinghaus <sns@severinghaus.org>

=head1 COPYRIGHT

Copyright (c) 2009 Steven N. Severinghaus. All rights reserved. This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

Finance::Bank::INGDirect, Finance::OFX::Parse::Simple

=cut

