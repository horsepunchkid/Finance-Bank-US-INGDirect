package Finance::Bank::US::INGDirect;

use strict;

use LWP::UserAgent;
use HTTP::Cookies;
use Data::Dumper;

my $base = 'https://secure.ingdirect.com/myaccount';

sub new {
    my ($class, %opts) = @_;
    my $self = bless \%opts, $class;

    $self->{ua} ||= LWP::UserAgent->new(cookie_jar => HTTP::Cookies->new);

    _login($self);
    $self;
}

sub _login {
    my ($self) = @_;

    my $response = $self->{ua}->get("$base/InitialINGDirect.html?command=displayLogin&locale=en_US&userType=Client&action=1");

    $response = $self->{ua}->post("$base/InitialINGDirect.html", [
        ACN => $self->{saver_id},
        command => 'customerIdentify',
        Locale => 'en_US',
        Device => 'web',
        UserType => 'Client',
        AuthenticationType => 'Primary',
        ApplicationType => 'ViewAccount',
        fp_browser => 'perl',
        fp_screen => 'big',
        fp_software => 'linux',
        from => 'PreviousPage',
        pageType => 'primary',
    ]);
    $response->is_redirect or die "Initial login failed.";

    $response = $self->{ua}->get("$base/INGDirect.html?command=displayCustomerAuthenticate&fill=&userType=Client");
    $response->is_success or die "Retrieving challenge questions failed.";
    # <input value="########" name="DeviceId" type="hidden">

    # Dig around for challenge questions
    #print grep /AnswerQ/, split('\n', $response->content) and exit;

    $response = $self->{ua}->post("$base/INGDirect.html", [
        command => 'customerAuthenticate',
        Locale => 'en_US',
        Device => 'web',
        UserType => 'Client',
        AuthenState => 'CONTINUE',
        AuthenticationType => 'Primary',
        ApplicationType => 'ViewAccount',
        QuestionHelpFlag => 'false',
        LoginStep => 'UnregisteredComputerChallengeQuestion',
        AlternateQuestionsSource => 'empty',
        isacif => 'true',
        'YES%2C+I+WANT+TO+CONTINUE.' => 'true',
        TLSearchNum => $self->{customer},
        ACN => $self->{saver_id},
        DeviceId => '', # Apparently unnecessary
        DeviceToken => $self->{ua}{cookie_jar}{COOKIES}{'.ingdirect.com'}{'/'}{'PMData'}[1],
        @{$self->{questions}},
    ]);
    $response->is_redirect or die "Submitting challenge responses failed.";

    $response = $self->{ua}->get("$base/INGDirect.html?command=displayCustomerAuthenticate&fill=&userType=Client");
    $response->is_success or die "Loading PIN form failed.";

    my @keypad = map { s/^.*addClick\('([A-Z]\.gif)\'.*$/$1/; $_ }
        grep /<img onmouseup="return addClick/,
        split('\n', $response->content);

    unshift(@keypad, pop @keypad);

    $response = $self->{ua}->post("$base/INGDirect.html", [
        command => 'customerAuthenticate',
        Locale => 'en_US',
        Device => 'web',
        UserType => 'Client',
        AuthenState => 'CONTINUE',
        AuthenticationType => 'Primary',
        ApplicationType => 'ViewAccount',
        QuestionHelpFlag => 'false',
        LoginStep => 'UnregisteredComputerPIN',
        AlternateQuestionsSource => 'empty',
        isacif => 'true',
        TLSearchNum => $self->{customer},
        ACN => $self->{saver_id},
        PIN => '****', # Literally what is submitted
        hc => '|'. join '|', map { $keypad[$_] } split//, $self->{pin},
    ]);
    $response->is_redirect or die "Submitting PIN failed.";

    $response = $self->{ua}->get("$base/INGDirect.html?command=viewAccountPostLogin&fill=&userType=Client");
    $response->is_success or die "Final login failed.";
    # Parse $response->content for current account status
}

sub last_month_qfx {
    my ($self) = @_;

    my $response = $self->{ua}->post("$base/download.qfx", [
        QFX => 'QFX',
        account => 'ALL',
        nickname => '',
        description => '',
        TIMEFRAME => 'STANDARD',
        FREQ => '30',
        RECMONTH => '0',
        RECDAY => '1',
        RECYEAR => '2000',
        EXPMONTH => '',
        EXPDAY => '',
        EXPYEAR => '',
    ]);
    $response->is_success or die "QFX download failed.";
    return $response->content;
}

1;

