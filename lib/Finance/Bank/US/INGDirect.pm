package Finance::Bank::US::INGDirect;

use strict;

use Carp 'croak';
use Finance::OFX;
use Finance::OFX::Institution;
use Finance::OFX::UserAgent;
use Finance::OFX::Account;
use Date::Parse;
use DateTime;
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

  my $ing = Finance::Bank::US::INGDirect->new(
      saver_id => '...',
      access_code => '...',
  );

  my %accounts = $ing->accounts;
  for (map { $accounts{$_} } keys %accounts) {
      print "Account: $_->{number} ($_->{nickname})\n";
      my @txns = $ing->recent_transactions($_->{number});
      printf "%s %-50s %8.2f\n", $_->{date}, $_->{name}, $_->{amount} for @txns;
      print "\n";
  }

=head1 DESCRIPTION

This module provides methods to access data from US INGdirect accounts,
including account balances and recent transactions via OFX (see
Finance::OFX and related modules).

=cut

=pod

=head1 METHODS

=head2 new( saver_id => '...', access_code => '...' )

Return an object that can be used to retrieve account balances and statements.

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

    $self->{accounts} = \%accounts;

    %accounts;
}

=pod

=head2 recent_transactions( $account, $days )

Retrieve a list of transactions in for the given account for the past
number of days (default: 30). See C<transactions> for return format.

=cut

sub recent_transactions {
    my ($self, $account, $days) = @_;

    $days ||= 30;

    my $end = DateTime->today;
    my $start = $end->clone->subtract(days => $days);

    $self->transactions($account, $start->ymd('-'), $end->ymd('-'));
}

=pod

=head2 transactions( $account, $from, $to )

Retrieve a list of transactions for the given account (default: all
accounts) in the given time frame (default: pretty far in the past to
pretty far in the future). The list returned contains hashes with keys
C<amount>, C<date>, C<name>, and C<fitid>.

=cut

sub transactions {
    my ($self, $account, $from, $to) = @_;

    $from ||= '2000-01-01';
    $to ||= '2038-01-01';

    my $end = str2time($to);
    my $start = str2time($from);

    my $a = Finance::OFX::Account->new(
        ID => $account,
        Type => uc($self->{accounts}{$account}{type}),
        FID => $self->{fi}->fid,
    );
    my $r = $self->{ofx}{ua}->statement($a, end => $end, start => $start, transactions => 1);
    my $txns = $r->ofx->{bankmsgsrsv1}{stmttrnrs}{stmtrs}{banktranlist}{stmttrn};
    return unless $txns;
    $txns = [ $txns ] if ref $txns eq 'HASH';
    map {
        $_->{amount} = sprintf('%.2f', $_->{trnamt});
        $_->{date} = DateTime->from_epoch(epoch => $_->{dtposted})->ymd('-');
        delete $_->{trnamt};
        delete $_->{trntype};
        delete $_->{dtposted};
        $_
    } @{$txns};
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

