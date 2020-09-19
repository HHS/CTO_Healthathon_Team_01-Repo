trigger TwilioMessage on TwilioSF__Message__c (before insert) {
    if(trigger.isBefore){
        TwilioMessageHandler.handleBeforeInsert(trigger.new);
    }
}