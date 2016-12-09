use strict;
use warnings;
use Email::Abstract;

use RT::Extension::ListAllEmailRecipients::Test tests => undef;

use_ok('RT::Extension::ListAllEmailRecipients');
my ($baseurl, $m) = RT::Test->started_ok;
diag "Base url is $baseurl";

my $user1 = RT::Test->load_or_create_user( EmailAddress => 'user1@example.com' );
my $user2 = RT::Test->load_or_create_user( EmailAddress => 'user2@example.com' );
my $user3 = RT::Test->load_or_create_user( EmailAddress => 'user3@example.com' );

# Update template with new variables
my $template = RT::Template->new(RT->SystemUser);
ok($template->Load('Correspondence in HTML'), 'Loaded Correspondence template');
$template->SetContent(q{
    RT-Attach-Message: yes

    The following people received a copy of this email:

    To: {$NotificationRecipientsTo}
    Cc: {$NotificationRecipientsCc}
    Bcc: {$NotificationRecipientsBcc}

    {$Transaction->Content()}
});

ok( RT::Test->add_rights({ Principal => 'Everyone', Right => [qw(ReplyToTicket Watch ShowTicket)] }), 'add ReplyToTicket rights');

my $ticket = RT::Test->create_ticket(
    Subject => 'Test adding recipients',
    Queue   => 'General',
);

$ticket->AddWatcher( Type => 'Requestor', Email => 'user1@example.com');
$ticket->AddWatcher( Type => 'Cc', Email => 'user2@example.com');
$ticket->AddWatcher( Type => 'AdminCc', Email => 'root@localhost');

my $ticket_id = $ticket->Id();
diag "Reply to ticket";
{
    my $text = <<EOF;
From: user3\@example.com
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [example.com #$ticket_id] Test adding recipients

This is a reply.
EOF

    RT::Test->clean_caught_mails;
    my $status;
    ($status, $ticket_id) = RT::Test->send_via_mailgate_and_http($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($ticket_id, "Replied to ticket");

    my $tick = RT::Test->last_ticket;
    isa_ok ($tick, 'RT::Ticket');
    is ($tick->Id, $ticket_id, "correct ticket id: $ticket_id");

    my $transactions = $tick->Transactions;
    $transactions->OrderByCols({ FIELD => 'id', ORDER => 'DESC' });
    $transactions->Limit(
        FIELD => 'Type',
        OPERATOR => 'ENDSWITH',
        VALUE => 'EmailRecord',
        ENTRYAGGREGATOR => 'AND',
    );
    my $txn = $transactions->First;
    my $content = $txn->Content;

    like( $content, qr/The following people received a copy of this email/,
        "Found 'received a copy' message in email");
    like( $content, qr/To\: user1\@example\.com/, 'user1 listed as To:');
    like( $content, qr/Cc\: user2\@example\.com/, 'user2 listed as Cc:');
    like( $content, qr/Bcc\: root\@localhost/, 'root listed as Bcc:');
}

undef $m;
done_testing;
