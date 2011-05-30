package Finance::Bank::US::INGDirect;

use strict;

use Carp 'croak';
use Finance::OFX;
use Finance::OFX::Institution;
use Finance::OFX::UserAgent;
use Finance::OFX::Account;
use Date::Parse;
use Data::Dumper;

=pod

=head1 NAME

Finance::Bank::US::INGDirect - Check balances and transactions for US INGDirect accounts

=head1 VERSION

Version 0.08

=cut

our $VERSION = '0.08';

=head1 SYNOPSIS

  use Finance::Bank::US::INGDirect;
  use Finance::OFX::Parse::Simple;

  my $ing = Finance::Bank::US::INGDirect->new(
      saver_id => '...',
      access_code => '...',
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
Finance::OFX and related modules). It also provides a method to transfer
money from one account to another on a given date.

=cut

my $base = '';

=pod

=head1 METHODS

=head2 new( saver_id => '...', customer => '...', questions => {...}, pin => '...' )

Return an object that can be used to retrieve account balances and statements.
See SYNOPSIS for examples of challenge questions.

=cut

sub new {
    my ($class, %opts) = @_;
    my $self = bless \%opts, $class;

    $self->{fi} = Finance::OFX::Institution->new(
        ORG => 'ING DIRECT',
        FID => '031176110',
        URL => 'https://ofx.ingdirect.com/OFX/ofx.html',
    );

    _login($self);
    $self;
}

sub _login {
    my ($self) = @_;

    $self->{ofx} = Finance::OFX->new(
        userID => $self->{saver_id},
        userPass => $self->{access_code},
        Institution => $self->{fi},
    );
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

    my %accounts = map {
        $_->{accttype} =~ s/(.)(.*)/\u$1\L$2/;
        $_->{acctid} => {
            type        => $_->{accttype},
            number      => $_->{acctid},
            nickname    => $_->{desc},
        }
    } $self->{ofx}->accounts;

    for(keys %accounts) {
        my $a = Finance::OFX::Account->new(
            ID => $accounts{$_}{number},
            Type => uc($accounts{$_}{type}),
            FID => $self->{fi}->fid,
        );
        my $r = $self->{ofx}{ua}->statement($a, end => time, start => time, transactions => 0);
        $r = $r->ofx->{bankmsgsrsv1}{stmttrnrs}{stmtrs};
        $accounts{$_}{available} = $r->{availbal}{balamt};
        $accounts{$_}{balance}   = $r->{ledgerbal}{balamt};
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
        startDate => sprintf("%02d/%02d/%d", @from[4,3,5]),
        endDate   => sprintf("%02d/%02d/%d", @to[4,3,5]),
    ]);
    $response->is_success or croak "OFX download failed.";

    $response->content;
}

1;

=pod

=head1 AUTHOR

This version by Steven N. Severinghaus <sns-perl@severinghaus.org>
with contributions by Robert Spier.

=head1 COPYRIGHT

Copyright (c) 2011 Steven N. Severinghaus. All rights reserved. This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

Finance::Bank::INGDirect, Finance::OFX::Parse::Simple

=cut

