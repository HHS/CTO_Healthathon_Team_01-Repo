public class TwilioMessageHandler {

    
    public static void handleBeforeInsert(List<TwilioSF__Message__c> messages){
        List<string> contactphones = new List<string>();
        
        for(TwilioSF__Message__c message: messages){
            if(message.TwilioSF__Direction__c == 'inbound'){
                
                String phoneNumber = message.TwilioSF__From_Number_Unformatted__c;
                
                contactphones.add(phoneNumber);
            }
        }
        
        System.debug(contactPhones);
        
        List<Contact> contactsList = [Select id,phone,mobilephone, firstname, Birthdate, dobVerified__c, community_worker__r.name, hematologist__r.name from contact where phone=: contactPhones OR mobilePhone=:contactPhones];
        Set<Id> contactIds = (new Map<Id,SObject>(contactsList)).keySet();
        
        System.debug(contactsList);
        
        Map<String, Contact> phoneToContact = new Map<String, Contact>();
        
        for(Contact c: contactsList){
            if(c.phone != null){
                phoneToContact.put(c.phone, c);
            }
            
            if(c.mobilePhone != null){
                phoneToContact.put(c.mobilePhone, c);
            }
            
        }
        
        List<SMSTrailStatus__c> TrailStatusToInsert = new List<SMSTrailStatus__c>();
      
        List<Contact> contactsToUpdate = new List<Contact>();
        
        
        List<SMSTrailStatus__c> smsStatusPrep = [Select id, contact__c, CurrentTrail__c  from SMSTrailStatus__c where contact__c =: contactIds order by CreatedDate DESC ];
        
        
        Map<id, SMSTrailStatus__c> previousSMSStatus = new Map<id, SMSTrailStatus__c>();
        
        for(SMSTrailStatus__c s: smsStatusPrep){
            if(previousSMSStatus.get(s.contact__c)==null){
                previousSMSStatus.put(s.contact__c,s);
            }
        }
        
        
        
        
        for(TwilioSF__Message__c message: messages){
            if(message.TwilioSF__Direction__c == 'inbound'){
                
                 String phoneNumber = message.TwilioSF__From_Number_Unformatted__c;

                
                if(TwilioMessageHandler.isValidEntry(message.TwilioSF__Body__c)){
                
                                            
                    if(phoneToContact.get(phoneNumber) != null){
                        Contact c = phoneToContact.get(phoneNumber);
                        
                        if(!c.dobVerified__c && message.TwilioSF__Body__c.toLowerCase() != 'sicklestrong'){
                           Boolean validatedBirthdate = TwilioMessageHandler.verifyDOB(message.TwilioSF__Body__c, c.Birthdate);
                            if(validatedBirthdate){
                                TwilioSF.TwilioSendSMS.sendSMSToNumber(phoneNumber,confirmedDobText(c.FirstName));
                                c.dobVerified__c = validatedBirthdate;
                                contactsToUpdate.add(c);
                            }else{
                                TwilioSF.TwilioSendSMS.sendSMSToNumber(phoneNumber,'I am sorry this birthdate is incorrect.');
                            }
                        }else{
                            
                            //Is a validated dob and not an entry message, let's process a response
                             System.debug('Prepping to send');
                            
                            SMSTrailStatus__c currentState = previousSMSStatus.get(c.id);
                            ResponseWrapper s = TwilioMessageHandler.processMessage(message.TwilioSF__Body__c, currentState, c);
                            
                            System.debug('RW: ' + s);
                            
                            if(s.currentStatus !=null){
                            	TrailStatusToInsert.add(s.currentStatus);
                            }
                            TwilioSF.TwilioSendSMS.sendSMSToNumber(phoneNumber,s.response);
                        }

                    }
                } else{
                    //Non-valid entry
                    TwilioSF.TwilioSendSMS.sendSMSToNumber(phoneNumber,'I am sorry this is an invalid entry.');                
                }
            
    	    }
        }
        
        //Update Contacts with validated dobs
		try{
            if(contactsToUpdate.Size()>0){
            	update contactsToUpdate;
            }
        }Catch(DMLException dmle){
            System.debug(dmle.getMessage());
        }

        system.debug(trailStatusToInsert);
        
		//Store the current status
        try{
            if(TrailStatusToInsert.size()>0){
            	insert TrailStatusToInsert;
            }
        }Catch(DMLException dmle){
            System.debug(dmle.getMessage());
        }

    }
    
    
    public static boolean verifyDOB(String message, Date dob){
        return (Date.parse(message) == dob);
    }
    
    public static responseWrapper processMessage(String messageText, SMSTrailStatus__c currentState, Contact c){
      
        System.debug(currentState);
        
        String response = 'Invalid Response';
        ResponseWrapper rw = new ResponseWrapper();
        
        if( messageText.toLowerCase() == 'sicklestrong'){
            
              SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = '_');
            
            response =  'Hello ' + c.firstName + ', We just need to confirm your identity. What is your date of birth? (in MM/DD/YYYY)';
            rw.response = response;
      		rw.currentStatus = futureState;
            
        }else if( messageText.toLowerCase() == '1' && (currentState == null || currentState.CurrentTrail__c.equals('_'))){
            
             SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'a');
            
          response =  'We hope you are staying strong. Which ER are you waiting at? \n 1) Emory University Hospital 2) Emory University Hospital Midtown 3) Grady Memorial Hospital 4) Northside Hospital 5) Piedmont Hospital 6) Saint Joseph\'s Hospital of Atlanta, 7) Wellstar Atlanta Medical Center';
      	 	rw.response = response;
            rw.currentStatus = futureState;
            
        }else if( TwilioMessagehandler.isValidSingleNumber(messageText) && currentState !=null && currentState.currentTrail__c.equals('a')) {
            
            String hospital = TwilioMessageHandler.processHospital(messageText);
            
            SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'e');
            
            response =  'Thank you. We have forwarded a message from your hematologist, '+ c.hematologist__r.name
                +' to the ER attending phone for '+  hospital
                +'. We have also notified ' + c.community_worker__r.name +' that you\'re in. Have you received pain medications yet? Please reply YES or NO.'; 
            
            rw.response = response;
            rw.currentStatus = futureState;
            
        }
        else if(messageText.toLowerCase() == 'yes' && currentState !=null && currentState.currentTrail__c.equals('e')){
            
            SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'j');
            
            response =  'Thank you for letting us know. We hope you can feel better soon. Do you feel that you are getting the care you deserve in the ER?'; 
            
            rw.response = response;
            rw.currentStatus = futureState;
            
            
            
        }else if((messageText.toLowerCase() == 'yes' || messageText.toLowerCase() == 'no') && currentState !=null && currentState.currentTrail__c.equals('j')){
            
            SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'k');
            
            response =  'Thank you for letting us know. We hope you can feel better soon. Do you feel that you are getting the care you deserve in the ER?'; 
            
            rw.response = response;
            rw.currentStatus = futureState;
            
            
        }else if( messageText.toLowerCase() == 'no' && currentState !=null && currentState.currentTrail__c.equals('k')){
             
            SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'z');
            
            response =  'Thank you. We hope you are able to get care soon. If you feel that you are being mistreated, please contact Condition H hotline at <Hospital Condition H Number>'; 
            
            rw.response = response;
            rw.currentStatus = futureState;
            
            
            
        }else if( messageText.toLowerCase() == 'yes' && currentState !=null && currentState.currentTrail__c.equals('k')){
            
            SMSTrailStatus__c futureState = new SMSTrailStatus__c(contact__c = c.id, currentTrail__c = 'z');
            
            response =  'Thank you for letting us know.';
            
			rw.response = response;
            rw.currentStatus = futureState;            
        }
        
        return rw;
        
    }
    
    public static string confirmedDobText(String contactName){
        String s = 'Hi ' + contactName +', Thanks for contacting #SickleStrong. Please reply with the number that applies to your situation so we can know how to best help you. If you\'d like to start the menu over, just text #SickleStrong to this number again.'
            + '1) I\'m in the ER for a pain crisis.'
            + '2) I\'d like to talk with another Sickle Cell Warrior to help me get through this.'
            + '3) I want to learn about joining the SickleStrong Network to help other SCWarriors. ';
        
        return s;
    }
    
    
    public static boolean isValidEntry(String entry){
        Pattern regEx = Pattern.compile('(^[0-9]{2}/[0-9]{2}/[0-9]{4}$)|^(?:Yes|No)$|^(?:yes|no)$|^([0-9]{1})$');
        Matcher regexMatcher = regEx.matcher(entry);
        boolean matches = entry.toLowerCase().equals('sicklestrong');
		return regexMatcher.matches()||matches;
    }
    
    public static boolean isValidSingleNumber(String entry){
        Pattern regEx = Pattern.compile('^[0-9]{1}$');
         Matcher regexMatcher = regEx.matcher(entry);
		return regexMatcher.matches();
    }
    
    public static string processHospital(String hospital){
        switch on hospital {
            when '1' {		
                return 'Emory University Hospital';
            }
            when '2' {
                return 'Emory University Hospital Midtown ';
            } 
            when '3' {
                return 'Grady Memorial Hospital';
            }
            when '4' {
                return 'Northside Hospital';
            }
            when '5' {
                return 'Piedmont Hospital';
            }
            when '6' {
                return 'Saint Joseph\'s Hospital of Atlanta';
            }
            when '7'{
                 return 'Wellstar Atlanta Medical Center ';
            }
        }
          return null;
        
    }
    
    public class responseWrapper{
        SMSTrailStatus__c currentStatus{get; set;}
        String response{get; set;}
        
    }
    
    
     /*TwilioSF__Message__c newResponse = new TwilioSF__Message__c();
                	newResponse.twiliosf__direction__c = 'outbound-api';
                    newResponse.TwilioSF__Body__c = TwilioMessageHandler.processMessage(message.TwilioSF__Body__c, '', c.firstName);
                    newResponse.TwilioSF__To_Number_Unformatted__c = phonenumber;
                    newResponse.TwilioSF__From_Number__c = '+14045281062';
                    responseMessages.add(newResponse);*/
}