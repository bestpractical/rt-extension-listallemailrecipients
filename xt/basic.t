use strict;
use warnings;
use Email::Abstract;

use RT::Extension::ListAllEmailRecipients::Test tests => undef;

use_ok('RT::Extension::ListAllEmailRecipients');
my ($baseurl, $m) = RT::Test->started_ok;
diag "Base url is $baseurl";

# Update template with placeholder
my $template = RT::Template->new(RT->SystemUser);
ok($template->Load('Correspondence in HTML'), 'Loaded Correspondence template');
$template->SetContent(q{
    RT-Attach-Message: yes

    The following people received a copy of this email:
    RT-INSERT-RECIPIENTS

    {$Transaction->Content()}
});


my $ticket = RT::Test->create_ticket(
    Subject => 'Test adding recipients',
    Queue   => 'General',
);

my $ticket_id = $ticket->Id();
diag "Test new ticket creation with message id";
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
RT-Send-CC: user1\@example.com
Subject: [example.com #$ticket_id] Test adding recipients

This is a reply.
EOF

    RT::Test->clean_caught_mails;
    my $status;
    ($status, $ticket_id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($ticket_id, "Replied to ticket");

    my $tick = RT::Test->last_ticket;
    isa_ok ($tick, 'RT::Ticket');
    is ($tick->Id, $ticket_id, "correct ticket id: $ticket_id");

    my @mail = map {Email::Abstract->new($_)->cast('MIME::Entity')}
        RT::Test->fetch_caught_mails;
    my $message_as_string = $mail[0]->bodyhandle->as_string();
    like( $message_as_string, qr/The following people received a copy of this email/,
        "Found 'received a copy' message in email");
    like( $message_as_string, qr/user1\@example\.com/, 'user1 listed as receiving email');
}


undef $m;
done_testing;
