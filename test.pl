#!/usr/bin/perl

use strict;

use Finance::Bank::US::INGDirect;

my %config = (
    saver_id => '',
    customer => '',
    questions => [
        'AnswerQ1.4' => '', # In what year was your mother born?
        'AnswerQ1.5' => '', # In what year was your father born?
        'AnswerQ1.8' => '', # What is the name of your hometown newspaper?
    ],
    pin => '',
);

my $ing = Finance::Bank::US::INGDirect->new(%config);

use Finance::OFX::Parse::Simple;

my $parser = Finance::OFX::Parse::Simple->new;
my @txs = @{$parser->parse_scalar($ing->recent_transactions)};
my %accounts = $ing->accounts;

for (@txs) {
    my $account = $accounts{$_->{account_id}};
    if($account) {
        print "$account->{type}: $account->{nickname} ($account->{number}) - \$$account->{balance}\n";
    }
    else {
        print "Account: $_->{account_id}\n";
    }
    printf "%s %-50s %8.2f\n", $_->{date}, $_->{name}, $_->{amount} for @{$_->{transactions}};
    print "\n";
}

